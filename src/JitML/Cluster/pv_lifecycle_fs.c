#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* All destructive operands are fixed here. The
 * caller owns the permanent lifecycle lock and has invalidated all selectors
 * and removed the exact cluster before this function may run. */
static int root_fd(const char *path) {
  if (!path || path[0] != '/') { errno=EINVAL; return -1; }
  char *copy=strdup(path);
  if (!copy) return -1;
  int fd=open("/",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
  if (fd<0) { free(copy); return -1; }
  char *save=NULL;
  for (char *part=strtok_r(copy,"/",&save); part; part=strtok_r(NULL,"/",&save)) {
    if (!strcmp(part,".") || !strcmp(part,"..")) { close(fd);free(copy);errno=EINVAL;return -1; }
    int next=openat(fd,part,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if (next<0) { int e=errno;close(fd);free(copy);errno=e;return -1; }
    close(fd);fd=next;
  }
  free(copy);return fd;
}

static int same_object(const struct stat *a,const struct stat *b) {
  return a->st_dev==b->st_dev && a->st_ino==b->st_ino &&
         (a->st_mode&S_IFMT)==(b->st_mode&S_IFMT);
}

static int runtime_fd(const char *workspace) {
  int root=root_fd(workspace);
  if (root<0) return -1;
  int build=openat(root,".build",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
  int error=errno;close(root);errno=error;
  if (build<0) return -1;
  int runtime=openat(build,"runtime",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
  error=errno;close(build);errno=error;return runtime;
}

int jitml_lifecycle_publication(const char *workspace) {
  int runtime=runtime_fd(workspace);
  if (runtime<0) return -1;
  int file=openat(runtime,"cluster-publication.json",O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);
  int error=errno;close(runtime);errno=error;return file;
}

static int exact_bytes(int fd,const unsigned char *expected,size_t length) {
  if (length>65536) { errno=EFBIG;return -1; }
  struct stat before,after;
  if (fstat(fd,&before)<0) return -1;
  if (!S_ISREG(before.st_mode) || before.st_nlink!=1 || before.st_size!=(off_t)length) { errno=EINVAL;return -1; }
  unsigned char bytes[65537];
  size_t count=0;
  for (;;) {
    ssize_t n=read(fd,bytes+count,sizeof bytes-count);
    if (n<0) { if (errno==EINTR) continue;return -1; }
    if (!n) break;
    count+=(size_t)n;
    if (count>length) { errno=EFBIG;return -1; }
  }
  if (fstat(fd,&after)<0) return -1;
  if (!same_object(&before,&after) || before.st_size!=after.st_size || count!=length || memcmp(bytes,expected,length)) { errno=ESTALE;return -1; }
  return 0;
}

/* Fixed-path, compare-before-replace stopped publication. This cannot create a
 * new authority for a missing publication or recreate a purged runtime root. */
int jitml_lifecycle_stopped(const char *workspace,const unsigned char *expected,size_t old_length,
                           const unsigned char *replacement,size_t new_length,const char *token) {
  if (old_length>65536 || new_length>65536 || !token || !*token || strlen(token)>100) { errno=EINVAL;return -1; }
  for (const char *p=token;*p;p++)
    if (!((*p>='a'&&*p<='z')||(*p>='0'&&*p<='9')||*p=='-')) { errno=EINVAL;return -1; }
  int runtime=runtime_fd(workspace);
  if (runtime<0) return -1;
  int current=openat(runtime,"cluster-publication.json",O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);
  if (current<0) { int e=errno;close(runtime);errno=e;return -1; }
  int result=exact_bytes(current,expected,old_length),error=errno;
  close(current);
  if (result<0) { close(runtime);errno=error;return -1; }
  char temporary[160];
  int n=snprintf(temporary,sizeof temporary,".cluster-publication-stopped-%s.tmp",token);
  if (n<0 || (size_t)n>=sizeof temporary) { close(runtime);errno=ENAMETOOLONG;return -1; }
  int file=openat(runtime,temporary,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
  if (file<0) { error=errno;close(runtime);errno=error;return -1; }
  size_t count=0;
  while (count<new_length) {
    ssize_t wrote=write(file,replacement+count,new_length-count);
    if (wrote<0) { if (errno==EINTR) continue;goto failed; }
    if (!wrote) { errno=EIO;goto failed; }
    count+=(size_t)wrote;
  }
  if (fsync(file)<0) goto failed;
  close(file);file=-1;
  current=openat(runtime,"cluster-publication.json",O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);
  if (current<0) goto failed;
  result=exact_bytes(current,expected,old_length);error=errno;close(current);errno=error;
  if (result<0 || renameat(runtime,temporary,runtime,"cluster-publication.json")<0 || fsync(runtime)<0) goto failed;
  current=openat(runtime,"cluster-publication.json",O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);
  if (current<0) goto failed;
  result=exact_bytes(current,replacement,new_length);error=errno;close(current);close(runtime);errno=error;return result;
failed:
  error=errno;if (file>=0) close(file);close(runtime);errno=error;return -1;
}

/* Descriptor-relative traversal never follows a directory or file symlink.
 * Links inside the explicitly purged tree are removed as links. */
static int empty_dir(int parent) {
  struct stat parent_status;
  if (fstat(parent,&parent_status)<0) return -1;
  int copy=dup(parent);
  if (copy<0) return -1;
  DIR *stream=fdopendir(copy);
  if (!stream) { int e=errno;close(copy);errno=e;return -1; }
  int result=0,error=0;
  for (;;) {
    errno=0;
    struct dirent *entry=readdir(stream);
    if (!entry) { if (errno) { result=-1;error=errno; } break; }
    const char *name=entry->d_name;
    if (!strcmp(name,".") || !strcmp(name,"..")) continue;
    struct stat before,opened,after;
    if (fstatat(parent,name,&before,AT_SYMLINK_NOFOLLOW)<0) { result=-1;error=errno;break; }
    if (S_ISDIR(before.st_mode)) {
      if (before.st_dev!=parent_status.st_dev) { result=-1;error=EXDEV;break; }
      int child=openat(parent,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
      if (child<0) { result=-1;error=errno;break; }
      if (fstat(child,&opened)<0) { result=-1;error=errno;close(child);break; }
      if (!same_object(&before,&opened)) { result=-1;error=ESTALE;close(child);break; }
      if (empty_dir(child)<0) { result=-1;error=errno;close(child);break; }
      close(child);
      if (fstatat(parent,name,&after,AT_SYMLINK_NOFOLLOW)<0) { result=-1;error=errno;break; }
      if (!same_object(&before,&after)) { result=-1;error=ESTALE;break; }
      if (unlinkat(parent,name,AT_REMOVEDIR)<0) { result=-1;error=errno;break; }
    } else if (unlinkat(parent,name,0)<0) { result=-1;error=errno;break; }
  }
  if (closedir(stream)<0 && result==0) { result=-1;error=errno; }
  if (result==0 && fsync(parent)<0) { result=-1;error=errno; }
  if (result<0) errno=error;
  return result;
}

/* Claim a fresh private quarantine directory, then detach the canonical root
 * into its absent payload name. A failed cleanup cannot restore the selector
 * under canonical .data, and an existing quarantine is never overwritten. */
static int detach_remove(int root,const char *source,const char *token,const char *suffix) {
  struct stat original,opened,again,workspace;
  if (fstat(root,&workspace)<0) return -1;
  if (fstatat(root,source,&original,AT_SYMLINK_NOFOLLOW)<0)
    return errno==ENOENT ? 0 : -1;
  if (!S_ISDIR(original.st_mode)) { errno=ENOTDIR;return -1; }
  if (original.st_dev!=workspace.st_dev) { errno=EXDEV;return -1; }
  char claim[240];
  int n=snprintf(claim,sizeof claim,".data-preserved-purge-%s-%s",token,suffix);
  if (n<0 || (size_t)n>=sizeof claim) { errno=ENAMETOOLONG;return -1; }
  if (mkdirat(root,claim,0700)<0) return -1;
  int quarantine=openat(root,claim,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
  if (quarantine<0) return -1;
  int result=-1,error=0;
  if (fsync(root)<0) goto done;
  if (fstatat(root,source,&again,AT_SYMLINK_NOFOLLOW)<0) goto done;
  if (!same_object(&original,&again)) { errno=ESTALE;goto done; }
  if (renameat(root,source,quarantine,"payload")<0) goto done;
  if (fsync(quarantine)<0 || fsync(root)<0) goto done;
  int payload=openat(quarantine,"payload",O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
  if (payload<0) goto done;
  if (fstat(payload,&opened)<0) { error=errno;close(payload);errno=error;goto done; }
  if (!same_object(&original,&opened)) { close(payload);errno=ESTALE;goto done; }
  if (empty_dir(payload)<0) { error=errno;close(payload);errno=error;goto done; }
  close(payload);
  if (unlinkat(quarantine,"payload",AT_REMOVEDIR)<0 || fsync(quarantine)<0) goto done;
  if (unlinkat(root,claim,AT_REMOVEDIR)<0 || fsync(root)<0) goto done;
  result=0;
done:
  error=errno;close(quarantine);errno=error;return result;
}

int jitml_lifecycle_purge(const char *workspace,const char *token,int full) {
  if (!token || !*token || strlen(token)>100 || (full!=0 && full!=1)) { errno=EINVAL;return -1; }
  for (const char *p=token;*p;p++)
    if (!((*p>='a'&&*p<='z')||(*p>='0'&&*p<='9')||*p=='-')) { errno=EINVAL;return -1; }
  int root=root_fd(workspace);
  if (root<0) return -1;
  int result=detach_remove(root,".data",token,"data");
  if (result==0 && full) result=detach_remove(root,".build",token,"build");
  int error=errno;close(root);errno=error;return result;
}
