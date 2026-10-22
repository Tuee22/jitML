"""Supplement the production publisher receipt with read-only physical hashes.

Usage: python3 inspect-physical-publication.py RECEIPT_DIRECTORY ROW_ID
This deliberately narrow CBOR reader does not perform production Store admission
or completion refinement. Those claims belong to the successful fresh publisher
invocation. No third-party Python modules or Haskell compilation are required.
"""

import argparse
import hashlib
import json
import pathlib
import re
import statistics
import struct


class CborReader:
    def __init__(self, payload):
        self.payload, self.position = payload, 0

    def take(self, count):
        value = self.payload[self.position:self.position + count]
        assert len(value) == count, "truncated CBOR"
        self.position += count
        return value

    def read(self):
        initial = self.take(1)[0]
        major, extra = initial >> 5, initial & 31
        if major == 7:
            if extra in (20, 21, 22):
                return {20: False, 21: True, 22: None}[extra]
            if extra in (25, 26, 27):
                size, code = {25: (2, "e"), 26: (4, "f"), 27: (8, "d")}[extra]
                return struct.unpack(">" + code, self.take(size))[0]
            raise ValueError(f"unsupported CBOR simple value {extra}")
        if extra < 24:
            count = extra
        elif extra in (24, 25, 26, 27):
            count = int.from_bytes(self.take(1 << (extra - 24)), "big")
        elif extra == 31 and major in (2, 3, 4):
            values = []
            while self.payload[self.position] != 255:
                values.append(self.read())
            self.take(1)
            return values if major == 4 else (b"".join(values) if major == 2 else "".join(values))
        else:
            raise ValueError(f"unsupported CBOR major/additional {major}/{extra}")
        if major == 0:
            return count
        if major == 1:
            return -1 - count
        if major in (2, 3):
            value = self.take(count)
            return value if major == 2 else value.decode("utf-8")
        if major == 4:
            return [self.read() for _ in range(count)]
        if major == 5:
            return {self.read(): self.read() for _ in range(count)}
        if major == 6:
            return {"cbor_tag": count, "value": self.read()}
        raise ValueError(f"unsupported CBOR major {major}")


def decode(payload):
    reader = CborReader(payload)
    result = reader.read()
    assert reader.position == len(payload), "trailing CBOR bytes"
    return result


def sha256(payload):
    return hashlib.sha256(payload).hexdigest()


def unwrap_maybe(value):
    # Codec.Serialise's Maybe encodes Nothing/Just as zero/one-element lists.
    assert isinstance(value, list) and len(value) <= 1, ("unexpected Maybe", value)
    return value[0] if value else None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("receipt_directory", type=pathlib.Path)
    parser.add_argument("row_id")
    parser.add_argument("--checkpoint-root", type=pathlib.Path, default=pathlib.Path(".build/checkpoints"))
    args = parser.parse_args()
    result = json.loads((args.receipt_directory / "result.json").read_text())
    assert result["exit_code"] == 0 and result["capture_complete"]
    stdout = (args.receipt_directory / "stdout.log").read_text()
    assert "reused admitted product-row checkpoint" not in stdout, "checkpoint reuse is not fresh execution"
    rows = [line.split("\t") for line in stdout.splitlines() if line.startswith("product-row\t" + args.row_id + "\t")]
    assert len(rows) == 1
    _, row, experiment, status, manifest_sha, message = rows[0]
    assert status == "eligible" and message == "RL policy artifact and trajectory stored and admitted"
    inventory = f"product-inventory\t{row}\t{experiment}\t{manifest_sha}\tadmitted"
    assert inventory in stdout.splitlines()
    assert re.fullmatch("[0-9a-f]{64}", manifest_sha)
    latest_path = args.checkpoint_root / "jitml-checkpoints" / experiment / "pointers" / "latest"
    latest_before = latest_path.read_bytes()
    assert latest_before == manifest_sha.encode(), "latest pointer differs from publisher admission address"
    manifest_path = args.checkpoint_root / "jitml-checkpoints" / experiment / "manifests" / (manifest_sha + ".cbor")
    manifest_bytes = manifest_path.read_bytes()
    assert sha256(manifest_bytes) == manifest_sha
    envelope = decode(manifest_bytes)
    assert len(envelope) == 4 and envelope[0] == 0
    _, version, body_hash, body_bytes = envelope
    assert sha256(body_bytes) == body_hash.hex()
    body = decode(body_bytes)
    assert len(body) == 2 and body[0] == 0, "expected weight-only manifest"
    raw = body[1]
    names = ["id", "experiment", "model_family", "architecture", "preprocessing", "output_decoders", "weight_layout", "replay_pointers", "transcript_pointers", "substrate_artifacts", "tensors", "optimizer", "rng", "step", "metrics", "plan_id", "completed_training", "initial_weight_hash", "final_weight_hash", "update_count", "dataset_sha_at_read", "parent_manifest_sha"]
    assert raw[0] == 0 and len(raw) == len(names) + 1
    manifest = dict(zip(names, raw[1:]))
    assert manifest["experiment"] == experiment
    plan_id = unwrap_maybe(manifest["plan_id"])
    final_weight_hash = unwrap_maybe(manifest["final_weight_hash"])
    completion = unwrap_maybe(manifest["completed_training"])
    assert completion[0] == 0 and completion[2] == plan_id
    evidence = completion[7]
    assert evidence[0] == 0 and evidence[2] == final_weight_hash
    assert evidence[3] == unwrap_maybe(manifest["update_count"])
    assert completion[5] == manifest["step"]
    raw_witness = unwrap_maybe(evidence[5])
    assert raw_witness[0] == 0 and len(raw_witness) == 7
    witness = dict(zip(["substrate", "backend", "kernel_hash", "artifact_path", "artifact_sha256", "executed_identity"], raw_witness[1:]))
    assert witness["substrate"] == "apple-silicon" and witness["backend"] == "metal"
    assert sha256(pathlib.Path(witness["artifact_path"]).read_bytes()) == witness["artifact_sha256"]
    tensors = []
    for tensor in manifest["tensors"]:
        assert len(tensor) == 4 and tensor[0] == 0
        _, name, shape, key = tensor
        physical = args.checkpoint_root / key
        payload = physical.read_bytes()
        actual = sha256(payload)
        assert actual == final_weight_hash
        logical_key = f"jitml-checkpoints/{experiment}/blobs/{actual}"
        assert key.split("/")[-1] == sha256(logical_key.encode())
        tensors.append({"name": name, "shape": shape, "object_key": key, "bytes": len(payload), "physical_sha256": actual})
    companions = []
    for pointer in manifest["transcript_pointers"]:
        assert len(pointer) == 4 and pointer[0] == 0
        _, kind, key, raw_digest = pointer
        expected = unwrap_maybe(raw_digest)
        payload = (args.checkpoint_root / key).read_bytes()
        assert sha256(payload) == expected
        companion = {"kind": kind, "object_key": key, "bytes": len(payload), "physical_sha256": expected}
        if kind == "rl-trajectory":
            lines = payload.decode().splitlines()
            rewards = [float(line.split(":", 1)[1]) for line in lines if line.startswith("episode-reward:")]
            steps = [int(line.split(":", 1)[1]) for line in lines if line.startswith("episode-steps:")]
            seed = [int(line.split(":", 1)[1]) for line in lines if line.startswith("seed:")]
            assert len(seed) == 1 and len(rewards) == len(steps)
            assert statistics.median(rewards) == dict(manifest["metrics"])["median_final_reward"]
            companion.update(seed=seed[0], episodes=len(rewards), median_reward=statistics.median(rewards), minimum_reward=min(rewards), maximum_reward=max(rewards), minimum_steps=min(steps), maximum_steps=max(steps))
        companions.append(companion)
    assert latest_path.read_bytes() == latest_before, "latest pointer changed during physical inspection"
    print(json.dumps({
        "scope": "read-only physical inspection; production exact Store admission is attested by the separate successful fresh publisher receipt, not reimplemented here",
        "row_id": row, "experiment": experiment, "publisher_message": message,
        "fresh_execution": True, "receipt": str(args.receipt_directory),
        "manifest_path": str(manifest_path), "manifest_bytes": len(manifest_bytes),
        "manifest_sha256": manifest_sha, "wire_version": version, "embedded_body_sha256": body_hash.hex(),
        "latest_pointer_path": str(latest_path), "latest_pointer_sha256_address": latest_before.decode(), "latest_pointer_stable_during_inspection": True,
        "plan_id": plan_id, "step": manifest["step"], "metrics": dict(manifest["metrics"]),
        "initial_weight_hash": unwrap_maybe(manifest["initial_weight_hash"]),
        "final_weight_hash": final_weight_hash, "update_count": unwrap_maybe(manifest["update_count"]),
        "dataset_sha_at_read": unwrap_maybe(manifest["dataset_sha_at_read"]),
        "completion_wire_version": completion[1], "completion_plan_id": completion[2],
        "completion_observed_units": completion[5], "completion_observed_unit_label": completion[6],
        "completion_training_evidence_raw": completion[7], "completion_measurements_raw": completion[8],
        "device_witness": witness, "device_artifact_physical_hash_matches": True,
        "tensors": tensors, "companions": companions,
    }, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
