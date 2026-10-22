"""Reproduce Phase 278's archive label/split diagnostic without model outputs.

Usage: python3 calculate-archive-label-baselines.py DATASET_DIRECTORY
Only labels and archive entry names are decoded; selected JPEG bytes are hashed
without pixel decoding. Every complete archive is SHA-256 checked against the
current production Dataset.hs before any is parsed.
This is neither a convergence policy nor a jitML validation gate.
"""

import argparse
import collections
import hashlib
import json
import pathlib
import re
import tarfile
import zipfile


ARTIFACTS = {
    "CIFAR-10": "cifar-10-binary.tar.gz",
    "CIFAR-100": "cifar-100-binary.tar.gz",
    "Tiny ImageNet": "tiny-imagenet-200.zip",
}
SOURCE_PATHS = [
    "src/JitML/SL/Dataset.hs",
    "src/JitML/SL/Classifier.hs",
    "src/JitML/SL/TinyImageNet.hs",
    "src/JitML/SL/TrainingExecution.hs",
    "src/JitML/Product/Matrix.hs",
]


def sha256_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def histogram(labels):
    counts = collections.Counter(labels)
    return {
        "examples": len(labels),
        "represented_classes": len(counts),
        "maximum_class_count": max(counts.values()),
        "counts": {str(label): count for label, count in sorted(counts.items())},
    }


def exact_uniform_random_floor(classes, examples=1000):
    # Prespecified in the retained review: alpha=.01 across 10 rows * 3 lanes.
    # This guards independent uniform predictions on any fixed label sequence.
    weights = [(classes - 1) ** examples]
    for index in range(examples):
        weights.append(weights[-1] * (examples - index) // ((index + 1) * (classes - 1)))
    denominator = classes ** examples
    assert sum(weights) == denominator
    tails = [0] * (examples + 1)
    remaining = 0
    for index in range(examples, -1, -1):
        remaining += weights[index]
        tails[index] = remaining
    minimum = next(index for index, tail in enumerate(tails) if tail * 3000 <= denominator)
    assert tails[minimum - 1] * 3000 > denominator
    return {
        "minimum_correct": minimum,
        "examples": examples,
        "familywise_alpha": "1/100",
        "comparisons": 30,
        "per_comparison_alpha": "1/3000",
        "tail_at_floor": tails[minimum] / denominator,
        "tail_one_below": tails[minimum - 1] / denominator,
    }


def cifar_labels(path, classes):
    if classes == 10:
        train_names = [f"cifar-10-batches-bin/data_batch_{index}.bin" for index in range(1, 6)]
        test_name = "cifar-10-batches-bin/test_batch.bin"
        record_size, offset = 3073, 0
    else:
        train_names = ["cifar-100-binary/train.bin"]
        test_name = "cifar-100-binary/test.bin"
        record_size, offset = 3074, 1
    decoded = {}
    wanted = set(train_names + [test_name])
    with tarfile.open(path, "r|gz") as archive:
        for member in archive:
            if member.name not in wanted:
                continue
            assert member.name not in decoded, "duplicate selected archive entry"
            assert member.isfile()
            payload = archive.extractfile(member).read()
            assert payload and len(payload) % record_size == 0
            labels = list(payload[offset::record_size])
            assert all(0 <= label < classes for label in labels)
            decoded[member.name] = labels
    assert set(decoded) == wanted
    train = [label for name in train_names for label in decoded[name]]
    test = decoded[test_name]
    assert len(train) == 50000 and len(test) == 10000
    return train, test, {
        "training_member_order": train_names,
        "evaluation_member": test_name,
        "record_bytes": record_size,
        "label_byte_offset": offset,
        "ordering": "record order within the explicitly ordered production members; no shuffle before prefix selection",
    }, None, None, None, None


def tiny_labels(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        assert len(names) == len(set(names)), "duplicate zip entry"
        wnids = [line.strip() for line in archive.read("tiny-imagenet-200/wnids.txt").decode().splitlines() if line.strip()]
        assert len(wnids) == len(set(wnids)) == 200
        label_map = {wnid: index for index, wnid in enumerate(wnids)}
        train_paths = sorted(name for name in names if name.startswith("tiny-imagenet-200/train/") and name.endswith(".JPEG"))
        train = [label_map[name.split("/")[2]] for name in train_paths]
        annotations = [line for line in archive.read("tiny-imagenet-200/val/val_annotations.txt").decode().splitlines() if line.strip()]
        test, evaluation_paths = [], []
        name_set = set(names)
        for line in annotations:
            image, wnid, x0, y0, x1, y1 = line.split("\t")
            tuple(map(int, (x0, y0, x1, y1)))
            assert "tiny-imagenet-200/val/images/" + image in name_set
            test.append(label_map[wnid])
            evaluation_paths.append("tiny-imagenet-200/val/images/" + image)
        interleaved_paths = class_interleaved_tiny_paths(train_paths, wnids)
        selected_paths = set(train_paths[:9600] + interleaved_paths[:9600] + evaluation_paths[:1000])
        image_hashes = {name: hashlib.sha256(archive.read(name)).hexdigest() for name in selected_paths}
    assert len(train) == 100000 and len(test) == 10000
    assert set(collections.Counter(train).values()) == {500}
    assert set(collections.Counter(test).values()) == {50}
    return train, test, {
        "training_order": "all train/ paths ending .JPEG, lexicographically sorted by full path before bounding",
        "class_index_order": "zero-based wnids.txt line order, not sorted wnids",
        "evaluation_order": "nonblank val/val_annotations.txt lines in file order; TestSplit aliases ValidationSplit",
        "training_prefix_first_path": train_paths[0],
        "training_prefix_last_path": train_paths[7999],
        "selection_prefix_first_path": train_paths[8000],
        "selection_prefix_last_path": train_paths[9599],
    }, wnids, train_paths, evaluation_paths, image_hashes


def image_split_identity(train_paths, evaluation_paths, image_hashes, train_examples=8000):
    train = train_paths[:train_examples]
    selection = train_paths[train_examples:train_examples + train_examples // 5]
    held_out = evaluation_paths[:1000]
    identities = {}
    for name, paths in (("training", train), ("selection_validation", selection), ("held_out_evaluation", held_out)):
        assert len(paths) == len(set(paths)), (name, "duplicate image path")
        identities[name + "_ordered_paths_sha256"] = hashlib.sha256("\n".join(paths).encode()).hexdigest()
        identities[name + "_ordered_jpeg_sha256s_digest"] = hashlib.sha256("\n".join(image_hashes[path] for path in paths).encode()).hexdigest()
    for name, left, right in (("training_selection", train, selection), ("training_evaluation", train, held_out), ("selection_evaluation", selection, held_out)):
        overlap = len(set(left) & set(right))
        assert overlap == 0, (name, overlap)
        identities[name + "_image_path_overlap"] = overlap
        shared_hashes = {image_hashes[path] for path in left} & {image_hashes[path] for path in right}
        identities[name + "_jpeg_content_sha256_overlap"] = len(shared_hashes)
        if shared_hashes:
            identities[name + "_shared_jpeg_content"] = [
                {"sha256": digest, "left_paths": [path for path in left if image_hashes[path] == digest], "right_paths": [path for path in right if image_hashes[path] == digest]}
                for digest in sorted(shared_hashes)
            ]
    return identities


def class_interleaved_tiny_paths(train_paths, wnids):
    grouped = {wnid: [] for wnid in wnids}
    for path in train_paths:
        grouped[path.split("/")[2]].append(path)
    for wnid in wnids:
        assert len(grouped[wnid]) == 500
        assert grouped[wnid] == sorted(grouped[wnid])
    interleaved = [grouped[wnid][index] for index in range(500) for wnid in wnids]
    assert len(interleaved) == len(train_paths)
    assert set(interleaved) == set(train_paths)
    return interleaved


def split_diagnostic(row, train_labels, held_out_labels, train_examples, classes, wnids):
    train = train_labels[:train_examples]
    selection = train_labels[train_examples:train_examples + train_examples // 5]
    held_out = held_out_labels[:1000]
    assert len(train) == train_examples and len(selection) == train_examples // 5 and len(held_out) == 1000
    train_classes, selection_classes, held_out_classes = map(set, (train, selection, held_out))
    train_counts = collections.Counter(train)
    held_out_counts = collections.Counter(held_out)
    train_majorities = sorted(label for label, count in train_counts.items() if count == max(train_counts.values()))
    random_floor = exact_uniform_random_floor(classes)
    constant_floor = max(held_out_counts.values()) + 1
    combined_floor = max(constant_floor, random_floor["minimum_correct"])
    result = {
        "row_id": row,
        "classes": classes,
        "training": histogram(train),
        "selection_validation": histogram(selection),
        "held_out_evaluation": histogram(held_out),
        "coverage": {
            "training_class_ids": sorted(train_classes),
            "selection_class_ids_absent_from_training": sorted(selection_classes - train_classes),
            "selection_examples_with_classes_absent_from_training": sum(label not in train_classes for label in selection),
            "held_out_class_ids_absent_from_training": sorted(held_out_classes - train_classes),
            "held_out_examples_with_classes_absent_from_training": sum(label not in train_classes for label in held_out),
            "held_out_examples_with_training_represented_classes": sum(label in train_classes for label in held_out),
            "training_selection_class_intersection": sorted(train_classes & selection_classes),
        },
        "constant_classifier_controls": {
            "training_majority_class_ids": train_majorities,
            "training_majority_tie_break": "lowest production label index",
            "training_majority_constant_held_out_correct": held_out_counts[train_majorities[0]],
            "best_held_out_constant_correct": max(held_out_counts.values()),
            "minimum_correct_rejecting_every_constant": constant_floor,
        },
        "uniform_random_control": random_floor,
        "proposed_additional_anti_trivial_minimum_correct": combined_floor,
        "proposed_additional_anti_trivial_accuracy": combined_floor / 1000,
    }
    if wnids:
        result["coverage"].update(
            training_wnids=[wnids[label] for label in sorted(train_classes)],
            selection_wnids=[wnids[label] for label in sorted(selection_classes)],
            training_labels_in_lexicographic_wnid_order=[wnids.index(wnid) for wnid in sorted(wnids[label] for label in train_classes)],
        )
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dataset_directory", type=pathlib.Path)
    parser.add_argument("--dataset", choices=ARTIFACTS, action="append", help="Limit diagnostics to selected verified archives")
    parser.add_argument("--repo-root", type=pathlib.Path, default=pathlib.Path(__file__).resolve().parents[3])
    args = parser.parse_args()
    source_bytes = {path: (args.repo_root / path).read_bytes() for path in SOURCE_PATHS}
    sources = {path: payload.decode() for path, payload in source_bytes.items()}
    assert "validationExamples = trainingExamples `div` 5" in sources["src/JitML/SL/TrainingExecution.hs"]
    assert "tiny-imagenet-training-class-interleaved-v1" in sources["src/JitML/SL/TinyImageNet.hs"]
    assert "List.sortOn (tinyZipPath . fst)" in sources["src/JitML/SL/TinyImageNet.hs"]
    assert "takeBound subsetLimit annotations" in sources["src/JitML/SL/TinyImageNet.hs"]
    matrix = sources["src/JitML/Product/Matrix.hs"]
    training_block = matrix.split("supervisedTrainingExampleCount rowId' =", 1)[1].split("supervisedEvaluationExampleCount ::", 1)[0]
    overrides = {name: int(count) for name, count in re.findall(r'"([^"]+)" -> (\d+)', training_block)}
    default_training = int(re.search(r"_ -> (\d+)", training_block).group(1))
    assert 'supervisedEvaluationExampleCount _ = 1000' in matrix
    verified = {}
    for dataset, filename in ARTIFACTS.items():
        if args.dataset and dataset not in args.dataset:
            continue
        expression = r'canonicalArtifactSha256For "' + re.escape(dataset) + r'" TrainSplit ArchiveArtifact =\s*(?:--[^\n]*\n\s*)*Just "([0-9a-f]{64})"'
        expected = re.search(expression, sources["src/JitML/SL/Dataset.hs"]).group(1)
        path = args.dataset_directory / filename
        actual = sha256_file(path)
        if actual != expected:
            raise ValueError(f"{filename}: SHA-256 {actual}, expected production pin {expected}; no archives parsed")
        verified[dataset] = {"filename": filename, "bytes": path.stat().st_size, "sha256": actual}
    classifications = [
        ("CIFAR-10", 10, ["cifar10-resnet20", "cifar10-resnet56", "cifar10-vit"]),
        ("CIFAR-100", 100, ["cifar100-wide-resnet"]),
        ("Tiny ImageNet", 200, ["tiny-imagenet-resnet50"]),
    ]
    diagnostics = {}
    for dataset, classes, rows in classifications:
        if args.dataset and dataset not in args.dataset:
            continue
        path = args.dataset_directory / ARTIFACTS[dataset]
        train, held_out, order, wnids, train_paths, evaluation_paths, image_hashes = tiny_labels(path) if classes == 200 else cifar_labels(path, classes)
        diagnostics[dataset] = {
            "decode_order": order,
            "full_training_label_histogram": histogram(train),
            "full_evaluation_label_histogram": histogram(held_out),
            "rows": [split_diagnostic(row, train, held_out, overrides.get(row, default_training), classes, wnids) for row in rows],
        }
        if classes == 200:
            historical = diagnostics[dataset].pop("rows")
            historical[0]["image_identity"] = image_split_identity(train_paths, evaluation_paths, image_hashes)
            interleaved_paths = class_interleaved_tiny_paths(train_paths, wnids)
            label_map = {wnid: index for index, wnid in enumerate(wnids)}
            interleaved_labels = [label_map[value.split("/")[2]] for value in interleaved_paths]
            prospective = split_diagnostic(rows[0], interleaved_labels, held_out, 8000, classes, wnids)
            prospective["image_identity"] = image_split_identity(interleaved_paths, evaluation_paths, image_hashes)
            assert all(value == 0 for name, value in prospective["image_identity"].items() if name.endswith("_jpeg_content_sha256_overlap"))
            assert prospective["training"]["represented_classes"] == 200
            assert set(prospective["training"]["counts"].values()) == {40}
            assert set(prospective["selection_validation"]["counts"].values()) == {8}
            assert prospective["coverage"]["selection_examples_with_classes_absent_from_training"] == 0
            assert prospective["coverage"]["held_out_examples_with_classes_absent_from_training"] == 0
            diagnostics[dataset]["historical_lexicographic_rows"] = historical
            diagnostics[dataset]["prospective_class_interleaved_rows"] = [prospective]
            diagnostics[dataset]["prospective_training_order"] = "round-robin across wnids.txt label order; each class retains lexicographically sorted JPEG paths; interleave before bounding"
            diagnostics[dataset]["historical_order_note"] = "decode_order and historical_lexicographic_rows explicitly reproduce the pre-repair lexicographic policy; prospective_class_interleaved_rows model the independently specified repair"
    print(json.dumps({
        "scope": "dataset-only label/split diagnostic; no model measurements, training, convergence-policy change or jitML gate invocation",
        "verification": "all complete artifact hashes match current production Dataset.hs before parsing any archive",
        "source_sha256": {path: hashlib.sha256(payload).hexdigest() for path, payload in source_bytes.items()},
        "selection_rule": "materialize trainingExamples + floor(trainingExamples/5); first trainingExamples for updates, remainder for selection validation",
        "verified_artifacts": verified,
        "datasets": diagnostics,
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
