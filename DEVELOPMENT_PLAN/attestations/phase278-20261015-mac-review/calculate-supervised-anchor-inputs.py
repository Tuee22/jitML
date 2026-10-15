"""Reproduce Phase 278's dataset-only review; never read trained measurements.

Usage: python3 calculate-supervised-anchor-inputs.py DATASET_DIRECTORY
The directory must contain the three upstream artifacts named below. Each full
artifact must match the production Dataset.hs SHA-256 pin before any parsing.
This analysis script is not an executable convergence policy or a gate receipt.
"""

import collections
import gzip
import hashlib
import json
import math
import pathlib
import struct
import sys
import tarfile


PINS = {
    "mnist-test-labels.gz": "f7ae60f92e00ec6debd23a6088c31dbd2371eca3ffa0defaefb259924204aec6",
    "fashion-test-labels.gz": "67da17c76eaffca5446c3361aaab5c3cd6d1c2608764d35dfb1850b086bf8dd5",
    "cal_housing.tgz": "aaa5c9a6afe2225cc2aed2723682ae403280c4a3695a2ddda4ffb5d8215ea681",
}


def histogram(labels):
    counts = collections.Counter(labels)
    return {
        "examples": len(labels),
        "represented_classes": len(counts),
        "maximum_class_count": max(counts.values()),
        "counts": dict(sorted(counts.items())),
    }


def exact_random_floor(classes, examples=1000):
    # For independent uniform class predictions, the exact count distribution
    # is Binomial(n, 1/C) conditional on ANY fixed sequence of true labels.
    # Alpha = .01 / (10 classification rows * 3 substrate lanes) = 1/3000.
    # Integer weights avoid normal approximations and floating tail decisions.
    weights = [(classes - 1) ** examples]
    for index in range(examples):
        weights.append(
            weights[-1] * (examples - index) // ((index + 1) * (classes - 1))
        )
    denominator = classes**examples
    assert sum(weights) == denominator
    tails = [0] * (examples + 1)
    remaining = 0
    for index in range(examples, -1, -1):
        remaining += weights[index]
        tails[index] = remaining
    threshold = next(
        index for index, tail in enumerate(tails) if tail * 3000 <= denominator
    )
    assert tails[threshold - 1] * 3000 > denominator
    return {
        "classes": classes,
        "examples": examples,
        "familywise_alpha": "1/100",
        "comparisons": 30,
        "per_comparison_alpha": "1/3000",
        "minimum_correct": threshold,
        "accuracy_floor": threshold / examples,
        "tail_at_floor": tails[threshold] / denominator,
        "tail_one_below": tails[threshold - 1] / denominator,
    }


def stats(values):
    mean = sum(values) / len(values)
    variance = sum((value - mean) ** 2 for value in values) / len(values)
    return mean, math.sqrt(variance)


root = pathlib.Path(sys.argv[1])
observed = {}
for name, expected in PINS.items():
    path = root / name
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    actual = digest.hexdigest()
    if actual != expected:
        raise ValueError(f"{name}: SHA-256 {actual}, expected {expected}")
    observed[name] = {"bytes": path.stat().st_size, "sha256": actual}

classification = {}
for dataset, filename in [
    ("MNIST", "mnist-test-labels.gz"),
    ("Fashion-MNIST", "fashion-test-labels.gz"),
]:
    labels = gzip.decompress((root / filename).read_bytes())
    magic, count = struct.unpack(">II", labels[:8])
    assert magic == 2049 and count == 10000 and len(labels) == count + 8
    classification[dataset] = histogram(list(labels[8:1008]))

with tarfile.open(root / "cal_housing.tgz", "r:gz") as archive:
    rows = archive.extractfile("CaliforniaHousing/cal_housing.data").read()
targets = [float(line.split(",")[-1]) for line in rows.decode().splitlines() if line.strip()]
assert len(targets) == 20640
train = targets[:7000]
held_out = targets[7000:8000]
train_mean, train_scale = stats(train)
standardized = [(value - train_mean) / train_scale for value in held_out]
evaluation_mean, evaluation_scale = stats(standardized)
regression = {
    "training_examples": len(train),
    "evaluation_examples": len(held_out),
    "training_target_mean_raw": train_mean,
    "training_target_scale_raw": train_scale,
    "held_out_target_mean_standardized": evaluation_mean,
    "best_constant_rmse_standardized": evaluation_scale,
    "training_mean_constant_rmse_standardized": math.sqrt(
        sum(value * value for value in standardized) / len(standardized)
    ),
    "positive_r_squared_requires": "rmse strictly below best_constant_rmse_standardized",
}

for values in classification.values():
    chance_floor = exact_random_floor(10)["minimum_correct"]
    values["proposed_additional_anti_trivial_minimum_correct"] = max(
        values["maximum_class_count"] + 1, chance_floor
    )

print(
    json.dumps(
        {
            "scope": "dataset-only independent review; no trained outputs, gate invocation, or policy change",
            "verified_artifacts": observed,
            "classification_held_out_prefixes": classification,
            "uniform_random_exact_binomial_controls": [
                exact_random_floor(classes) for classes in (10, 100, 200)
            ],
            "california_housing": regression,
        },
        indent=2,
        sort_keys=True,
    )
)
