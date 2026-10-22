#!/usr/bin/env python3
"""Summarize retained short-prefix traces; never runs training or publishes.

Usage: analyze-trpo-prefix.py RAW_OUTPUT_DIRECTORY OUTPUT.json
Requires only the Python standard library. Large raw operation traces stay in
the ignored build directory; output identities make their exact bytes explicit.
"""
import hashlib
import json
import math
import pathlib
import struct
import sys


def identity(path):
    return {"path": str(path), "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest()}


def flatten(parts):
    return [v for part in parts for v in part]


def blocks(values):
    offsets = [0, 1024, 1280, 2048, 2051]
    return [values[a:b] for a, b in zip(offsets, offsets[1:])]


def dot(a, b):
    # Match the four ordered vector reductions and left-associated block sums.
    sums = [sum(x*y for x, y in zip(aa, bb))
            for aa, bb in zip(blocks(a), blocks(b))]
    return ((sums[0]+sums[1])+sums[2])+sums[3]


def fbits(x):
    return struct.unpack("<I", struct.pack("<f", x))[0]


def softmax(row):
    logits = row[:2]
    shifted = [math.exp(x-max(logits)) for x in logits]
    return [x/sum(shifted) for x in shifted]


def analyze_iteration(full, final_result):
    actor, actor_gradient, current = full[:3]
    assert [e["operation"] for e in full[:3]] == ["forward_batch", "batch_gradient", "forward_batch"]
    base = flatten(actor["full_batch_parameter_values"])
    b = [x/8192 for x in flatten(actor_gradient["full_batch_output_values"])]
    x = [0.0]*len(b)
    r = b[:]
    direction = b[:]
    rr = dot(b, b)
    operators = []
    position = 3
    # Consecutive forward, forward, gradient triples are FD Fisher operations.
    while position+2 < len(full) and [e["operation"] for e in full[position:position+3]] == ["forward_batch", "forward_batch", "batch_gradient"]:
        plus, minus, gradient = full[position:position+3]
        position += 3
        is_curvature = position >= len(full) or full[position]["operation"] != "forward_batch" or position+2 >= len(full) or full[position+2]["operation"] != "batch_gradient"
        d = x if is_curvature else direction
        norm = math.sqrt(max(0, dot(d, d)))
        epsilon = 1e-3/max(1, norm)
        pp = flatten(plus["full_batch_parameter_values"])
        mm = flatten(minus["full_batch_parameter_values"])
        active = [i for i, value in enumerate(d) if value != 0]
        collapsed = sum(fbits(pp[i]) == fbits(mm[i]) for i in active)
        pp_expected = [a+epsilon*v for a, v in zip(base, d)]
        mm_expected = [a-epsilon*v for a, v in zip(base, d)]
        parameter_error = max(abs(a-b) for a, b in zip(pp+mm, pp_expected+mm_expected))
        ap = [g/8192+0.1*v for g, v in zip(flatten(gradient["full_batch_output_values"]), d)]
        curvature = dot(d, ap)
        item = {"kind": "final_natural_direction_curvature" if is_curvature else "cg_direction",
                "plus_ordinal": plus["ordinal"], "minus_ordinal": minus["ordinal"],
                "gradient_ordinal": gradient["ordinal"], "direction_norm": norm,
                "epsilon": epsilon, "active_direction_elements": len(active),
                "collapsed_active_float32_elements": collapsed,
                "perturbation_reconstruction_max_absolute_error": parameter_error,
                "direction_dot_fisher_direction": curvature,
                "zero_logit_jvp_coordinates": sum(a == b for p, m in zip(plus["full_batch_output_values"], minus["full_batch_output_values"]) for a, b in zip(p[:2], m[:2]))}
        # Reconstruction uses independently replayed host Double arithmetic.
        # A finite max error is retained instead of claiming hidden CG hooks.
        if not is_curvature:
            item["residual_squared_before"] = rr
            if curvature <= 1e-20:
                item["cg_truncated_nonpositive_curvature"] = True
            else:
                alpha = rr/curvature
                x = [a+alpha*v for a, v in zip(x, d)]
                r = [a-alpha*v for a, v in zip(r, ap)]
                rr_next = dot(r, r)
                beta = rr_next/rr
                direction = [a+beta*v for a, v in zip(r, d)]
                rr = rr_next
                item.update(alpha=alpha, beta=beta, residual_squared_after=rr)
        operators.append(item)
    candidates = full[position:]
    old_policies = [softmax(row) for row in current["full_batch_output_values"]]
    candidate_summaries = []
    for index, candidate in enumerate(candidates):
        policies = [softmax(row) for row in candidate["full_batch_output_values"]]
        kl = sum(max(0, sum(p*(math.log(p)-math.log(q)) for p, q in zip(old, new) if p > 0)) for old, new in zip(old_policies, policies))/8192
        trust_scale = math.sqrt(0.02/operators[-1]["direction_dot_fisher_direction"])
        expected = [a-(0.8**index)*trust_scale*v for a, v in zip(base, x)]
        actual = flatten(candidate["full_batch_parameter_values"])
        candidate_summaries.append({"ordinal": candidate["ordinal"], "backtrack_index": index,
                                    "backtrack_scale": 0.8**index, "exact_categorical_kl_recomputed_from_traced_logits": kl,
                                    "candidate_parameter_reconstruction_max_absolute_error": max(abs(a-b) for a, b in zip(expected, actual)),
                                    "surrogate_loss": None,
                                    "surrogate_loss_unavailable_reason": "sampled actions and unrounded GAE advantages are not exposed by this operation seam"})
    return {"full_batch_operation_ordinals": [e["ordinal"] for e in full],
            "fisher_operator_reconstruction": operators, "line_search_candidates": candidate_summaries,
            "line_search_acceptance": "last candidate accepted: trainer proceeded to critic updates; actor slices are restored during each critic step",
            "critic_loss": None,
            "critic_loss_unavailable_reason": "critic per-example targets are not retained by the production result seam"}


def main():
    raw, output = map(pathlib.Path, sys.argv[1:])
    summary = json.loads((raw/"summary.json").read_text())
    metal = [json.loads(line) for line in (raw/"metal-shadow.jsonl").read_text().splitlines()]
    reference = [json.loads(line) for line in (raw/"float32-reference.jsonl").read_text().splitlines()]
    assert len(metal) == len(reference)
    comparison = {}
    for field in ["operation", "batch_size", "parameters", "inputs", "upstream", "outputs"]:
        different = [{"ordinal": a["ordinal"], "operation": a["operation"], "batch_size": a["batch_size"]}
                     for a, b in zip(metal, reference) if a[field] != b[field]]
        comparison[field] = {"different_operation_count": len(different), "first_different_operation": different[0] if different else None}
    different = [e for e in metal if e["shadow_difference"]["different_float_bits"]]
    numeric = [e for e in different if e["shadow_difference"]["max_absolute_difference"] != 0]
    full = [e for e in metal if e["batch_size"] == 8192]
    iterations = []
    group = []
    # Each rollout resets the full-batch sequence to a gradient preparation
    # followed by its unperturbed policy gradient. Candidate parameters differ.
    for e in full:
        if group and e["operation"] == "forward_batch" and e["ordinal"] > group[-1]["ordinal"]+1:
            iterations.append(group)
            group = []
        group.append(e)
    if group:
        iterations.append(group)
    result = {"schema": "jitml-trpo-prefix-analysis-v1", "scope": "diagnostic only; no canonical convergence or publication claim",
              "raw_summary": summary, "raw_files": [identity(p) for p in sorted(raw.iterdir()) if p.is_file()],
              "operation_count_per_device": len(metal), "operation_trace_comparison": comparison,
              "shadow_different_bit_operation_count": len(different), "shadow_numeric_difference_operation_count": len(numeric),
              "first_shadow_bit_difference": {k: different[0][k] for k in ["ordinal", "operation", "batch_size", "shadow_difference"]} if different else None,
              "first_shadow_numeric_difference": {k: numeric[0][k] for k in ["ordinal", "operation", "batch_size", "shadow_difference"]} if numeric else None,
              "minimal_fisher_homogeneity_probe": json.loads((raw/"fisher-minimal.json").read_text()),
              "iterations": [analyze_iteration(g, None) for g in iterations]}
    assert len(iterations) == summary["iterations"]
    assert max(op["perturbation_reconstruction_max_absolute_error"] for iteration in result["iterations"] for op in iteration["fisher_operator_reconstruction"]) < 1e-10
    output.write_text(json.dumps(result, indent=2)+"\n")
    print(f"Analyzed {len(metal)} operations per device across {len(iterations)} iterations; {len(numeric)} nonzero shadow differences; output {output}")


if __name__ == "__main__":
    main()
