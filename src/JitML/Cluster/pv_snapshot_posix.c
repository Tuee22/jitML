#define _GNU_SOURCE
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <dirent.h>

/* All names are single, validated components; traversal is owned by Haskell. */
int jitml_pv_root(void) { return open("/", O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC); }
int jitml_pv_dir(int parent, const char *name) {
  return openat(parent,name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
}
int jitml_pv_mkdir(int parent, const char *name) { return mkdirat(parent,name,0700); }
int jitml_pv_file(int parent, const char *name, int how) {
  int flags = O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK;
  if (how == 0) flags |= O_RDONLY;
  else if (how == 1) flags |= O_RDWR|O_CREAT|O_EXCL;
  else if (how == 2) flags |= O_RDWR|O_CREAT;
  else if (how == 3) flags |= O_RDWR|O_APPEND;
  else { errno=EINVAL; return -1; }
  return openat(parent,name,flags,0600);
}
int jitml_pv_sync(int fd) { return fsync(fd); }
int jitml_pv_rename(int parent, const char *from, const char *to) {
  return renameat(parent,from,parent,to);
}
int jitml_pv_lock(int fd) { return flock(fd,LOCK_EX); }
int jitml_pv_unlock(int fd) { return flock(fd,LOCK_UN); }

static const char *claim_name = ".jitml-pv-lifecycle.claim.lock";

static int token_ok(const char *token) {
  if (!token || !*token || strlen(token)>160) return 0;
  for (const char *p=token;*p;p++)
    if (!( (*p>='a'&&*p<='z') || (*p>='A'&&*p<='Z') ||
           (*p>='0'&&*p<='9') || *p=='-' || *p=='_')) return 0;
  return 1;
}

static int same_object(const struct stat *a,const struct stat *b) {
  return a->st_dev==b->st_dev && a->st_ino==b->st_ino &&
    (a->st_mode&S_IFMT)==(b->st_mode&S_IFMT);
}

static int same_file(const struct stat *a,const struct stat *b) {
  if (!same_object(a,b) || a->st_mode!=b->st_mode || a->st_uid!=b->st_uid ||
      a->st_gid!=b->st_gid || a->st_nlink!=b->st_nlink || a->st_size!=b->st_size) return 0;
#ifdef __APPLE__
  return a->st_mtimespec.tv_sec==b->st_mtimespec.tv_sec &&
    a->st_mtimespec.tv_nsec==b->st_mtimespec.tv_nsec &&
    a->st_ctimespec.tv_sec==b->st_ctimespec.tv_sec &&
    a->st_ctimespec.tv_nsec==b->st_ctimespec.tv_nsec;
#else
  return a->st_mtim.tv_sec==b->st_mtim.tv_sec && a->st_mtim.tv_nsec==b->st_mtim.tv_nsec &&
    a->st_ctim.tv_sec==b->st_ctim.tv_sec && a->st_ctim.tv_nsec==b->st_ctim.tv_nsec;
#endif
}

/* mkdirat is the cross-kernel exclusive claim. EEXIST is BUSY, never a stale
 * PID inference. Partial acquisition/crash leaves a claim for verified recovery. */
int jitml_pv_claim_acquire(int root,const char *token) {
  if (!token_ok(token)) { errno=EINVAL;return -1; }
  if (mkdirat(root,claim_name,0700)<0) return -1;
  int claim=openat(root,claim_name,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
  if (claim<0) return -1;
  int owner=openat(claim,"owner",O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW|O_CLOEXEC,0600);
  if (owner<0) { int error=errno;close(claim);errno=error;return -1; }
  char bytes[162];size_t size=strlen(token)+1;
  memcpy(bytes,token,size-1);bytes[size-1]='\n';
  size_t offset=0;
  while (offset<size) {
    ssize_t count=write(owner,bytes+offset,size-offset);
    if (count<0 && errno==EINTR) continue;
    if (count<=0) { int error=count==0?EIO:errno;close(owner);close(claim);errno=error;return -1; }
    offset+=(size_t)count;
  }
  int error=0;
  if (fsync(owner)<0) error=errno;
  if (close(owner)<0 && !error) error=errno;
  if (!error && fsync(claim)<0) error=errno;
  if (!error && fsync(root)<0) error=errno;
  if (error) { close(claim);errno=error;return -1; }
  return claim;
}

/* Release only our held directory and exact immutable owner token. Unexpected
 * content/identity means retain the claim, fail closed and require inspection. */
int jitml_pv_claim_release(int root,int claim,const char *token) {
  if (!token_ok(token)) { errno=EINVAL;return -1; }
  struct stat held,named,before,after,owner_named;
  if (fstat(claim,&held)<0 || fstatat(root,claim_name,&named,AT_SYMLINK_NOFOLLOW)<0) return -1;
  if (!same_object(&held,&named) || !S_ISDIR(held.st_mode) ||
      (held.st_mode&07777)!=0700 || held.st_uid!=geteuid() || held.st_gid!=getegid()) { errno=ESTALE;return -1; }
  int owner=openat(claim,"owner",O_RDONLY|O_NOFOLLOW|O_CLOEXEC|O_NONBLOCK);
  if (owner<0) return -1;
  if (fstat(owner,&before)<0) { int error=errno;close(owner);errno=error;return -1; }
  size_t size=strlen(token)+1;
  if (!S_ISREG(before.st_mode) || before.st_nlink!=1 || (before.st_mode&07777)!=0600 ||
      before.st_uid!=geteuid() || before.st_gid!=getegid() || before.st_size!=(off_t)size) {
    close(owner);errno=ESTALE;return -1;
  }
  char bytes[163];size_t count=0;
  for (;;) {
    ssize_t n=read(owner,bytes+count,sizeof bytes-count);
    if (n<0 && errno==EINTR) continue;
    if (n<0) { int error=errno;close(owner);errno=error;return -1; }
    if (!n) break;
    count+=(size_t)n;
    if (count>size) { close(owner);errno=ESTALE;return -1; }
  }
  if (fstat(owner,&after)<0 || fstatat(claim,"owner",&owner_named,AT_SYMLINK_NOFOLLOW)<0) {
    int error=errno;close(owner);errno=error;return -1;
  }
  close(owner);
  if (!same_file(&before,&after) || !same_file(&before,&owner_named) || count!=size ||
      memcmp(bytes,token,size-1) || bytes[size-1]!='\n') { errno=ESTALE;return -1; }
  int copy=dup(claim);
  if (copy<0) return -1;
  DIR *stream=fdopendir(copy);
  if (!stream) { int error=errno;close(copy);errno=error;return -1; }
  int extra=0,error=0;
  for (;;) {
    errno=0;struct dirent *entry=readdir(stream);
    if (!entry) { if(errno) error=errno;break; }
    if (strcmp(entry->d_name,".") && strcmp(entry->d_name,"..") && strcmp(entry->d_name,"owner")) extra=1;
  }
  if (closedir(stream)<0 && !error) error=errno;
  if (error || extra) { errno=error?error:ENOTEMPTY;return -1; }
  if (fstatat(root,claim_name,&named,AT_SYMLINK_NOFOLLOW)<0 || !same_object(&held,&named)) { errno=ESTALE;return -1; }
  if (unlinkat(claim,"owner",0)<0 || fsync(claim)<0) return -1;
  if (fstatat(root,claim_name,&named,AT_SYMLINK_NOFOLLOW)<0 || !same_object(&held,&named)) { errno=ESTALE;return -1; }
  if (unlinkat(root,claim_name,AT_REMOVEDIR)<0 || fsync(root)<0) return -1;
  return 0;
}
