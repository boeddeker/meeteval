# distutils: language = c++
#cython: language_level=3

import numpy as np
from libcpp.vector cimport vector
from libcpp.pair cimport pair

ctypedef unsigned int uint

cdef extern from "levenshtein.h":
    uint levenshtein_distance_(
            vector[uint] reference,
            vector[uint] hypothesis,
    )

    uint levenshtein_distance_custom_cost_(
            vector[uint] reference,
            vector[uint] hypothesis,
            uint cost_del,
            uint cost_ins,
            uint cost_sub,
            uint cost_cor,
    )

    uint time_constrained_levenshtein_distance_[T](
            vector[uint] reference,
            vector[uint] hypothesis,
            vector[pair[T, T]] reference_timing,
            vector[pair[T, T]] hypothesis_timing,
            uint cost_del,
            uint cost_ins,
            uint cost_sub,
            uint cost_cor,
    )

    uint time_constrained_levenshtein_distance_unoptimized_[T](
            vector[uint] reference,
            vector[uint] hypothesis,
            vector[pair[T, T]] reference_timing,
            vector[pair[T, T]] hypothesis_timing,
            uint cost_del,
            uint cost_ins,
            uint cost_sub,
            uint cost_cor,
    )

    struct LevenshteinStatistics:
        uint insertions
        uint deletions
        uint substitutions
        uint correct
        uint total
        vector[pair[uint, uint]] alignment

    LevenshteinStatistics time_constrained_levenshtein_distance_with_alignment_[T](
            vector[uint] reference,
            vector[uint] hypothesis,
            vector[pair[T, T]] reference_timing,
            vector[pair[T, T]] hypothesis_timing,
            uint cost_del,
            uint cost_ins,
            uint cost_sub,
            uint cost_cor,
            uint eps
    )


def obj2vec(a, b):
    # Taken from kaldialign https://github.com/pzelasko/kaldialign/blob/17d2b228ec575aa4f45ff2a191fb4716e83db01e/kaldialign/__init__.py#L6-L15
    int2sym = dict(enumerate(sorted(set(a) | set(b))))
    sym2int = {v: k for k, v in int2sym.items()}
    return [sym2int[a_] for a_ in a], [sym2int[b_] for b_ in b]


def _validate_costs(cost_del, cost_ins, cost_sub, cost_cor):
    if not (isinstance(cost_del, int) and isinstance(cost_ins, int) and isinstance(cost_sub, int) and isinstance(
            cost_cor, int)):
        raise ValueError(
            f'Only unsigned integer costs are supported, but found cost_del={cost_del}, '
            f'cost_ins={cost_ins}, cost_sub={cost_sub}, cost_cor={cost_cor}'
        )

def levenshtein_distance(
        reference,
        hypothesis,
        cost_del=1,
        cost_ins=1,
        cost_sub=1,
        cost_cor=0,
):
    reference, hypothesis = obj2vec(reference, hypothesis)
    if cost_del == 1 and cost_ins == 1 and cost_sub == 1 and cost_cor == 0:
        # This is the fast case where we can use the standard optimized algorithm
        return levenshtein_distance_(reference, hypothesis)

    _validate_costs(cost_del, cost_ins, cost_sub, cost_cor)

    return levenshtein_distance_custom_cost_(
        reference, hypothesis, cost_del, cost_ins, cost_sub, cost_cor
    )

def _validate_inputs(reference, hypothesis, reference_timing, hypothesis_timing):
    if len(reference) != len(reference_timing):
        raise ValueError(
            f'reference and reference_timing have mismatching lengths '
            f'{len(reference)} != {len(reference_timing)}'
        )
    if len(hypothesis) != len(hypothesis_timing):
        raise ValueError(
            f'hypothesis and hypothesis_timing have mismatching lengths '
            f'{len(hypothesis)} != {len(hypothesis_timing)}'
        )

    reference_timing = np.array(reference_timing)
    hypothesis_timing = np.array(hypothesis_timing)

    assert len(reference) == 0 or reference_timing.shape == (len(reference), 2), (
    reference_timing.shape, len(reference))
    assert len(hypothesis) == 0 or hypothesis_timing.shape == (len(hypothesis), 2), (
    hypothesis_timing.shape, len(hypothesis))
    assert len(reference) == 0 or len(hypothesis) == 0 or reference_timing.dtype == hypothesis_timing.dtype, (
    reference_timing.dtype, hypothesis_timing.dtype)

    def check(timing, info):
        # end >= start
        if np.any(timing[:, 1] < timing[:, 0]):
            raise ValueError(
                f'The end time of an interval must not be smaller than its begin time, but the {info} violates this')
        # start values are increasing
        if np.any(np.diff(timing[:, 0]) < 0):
            raise ValueError(
                f'The start times of the annotations must be increasing, which they are not for the {info}. '
                f'This might be caused by overlapping segments, see the (potential) previous warning.'
            )

    if len(reference):
        check(reference_timing, 'reference')
    if len(hypothesis):
        check(hypothesis_timing, 'hypothesis')

    return reference, hypothesis, reference_timing, hypothesis_timing

def time_constrained_levenshtein_distance(
        reference,  # list[int]
        hypothesis,  # list[int]
        reference_timing,  # list[tuple[int, int]]
        hypothesis_timing,  # list[tuple[int, int]]
        cost_del: uint = 1,
        cost_ins: uint = 1,
        cost_sub: uint = 1,
        cost_cor: uint = 0,
):
    _validate_costs(cost_del, cost_ins, cost_sub, cost_cor)
    reference, hypothesis, reference_timing, hypothesis_timing = _validate_inputs(
        reference, hypothesis, reference_timing, hypothesis_timing
    )

    if len(reference) == 0:
        return len(hypothesis) * cost_ins
    if len(hypothesis) == 0:
        return len(reference) * cost_del
    reference, hypothesis = obj2vec(reference, hypothesis)

    args = (reference, hypothesis,
            reference_timing,
            hypothesis_timing,
            cost_del,
            cost_ins,
            cost_sub,
            cost_cor,)
    if np.issubdtype(reference_timing.dtype, np.signedinteger):
        return time_constrained_levenshtein_distance_[int](*args)
    elif np.issubdtype(reference_timing.dtype, np.unsignedinteger):
        return time_constrained_levenshtein_distance_[uint](*args)
    elif np.issubdtype(reference_timing.dtype, np.floating):
        return time_constrained_levenshtein_distance_[double](*args)
    else:
        raise TypeError(reference_timing.dtype)

def time_constrained_levenshtein_distance_unoptimized(
        reference,  # list[int]
        hypothesis,  # list[int]
        reference_timing,  # list[tuple[int, int]]
        hypothesis_timing,  # list[tuple[int, int]]
        cost_del=1,
        cost_ins=1,
        cost_sub=1,
        cost_cor=0,
):
    """
    The time-constrained levenshtein distance without time-pruning optimization. This mainly exists so we
    can test the optimized implementation against this one.
    """
    _validate_costs(cost_del, cost_ins, cost_sub, cost_cor)
    reference, hypothesis, reference_timing, hypothesis_timing = _validate_inputs(
        reference, hypothesis, reference_timing, hypothesis_timing
    )
    if len(reference) == 0:
        return len(hypothesis) * cost_ins
    if len(hypothesis) == 0:
        return len(reference) * cost_del
    reference, hypothesis = obj2vec(reference, hypothesis)

    args = (reference, hypothesis,
            reference_timing,
            hypothesis_timing,
            cost_del,
            cost_ins,
            cost_sub,
            cost_cor,)
    if np.issubdtype(reference_timing.dtype, np.signedinteger):
        return time_constrained_levenshtein_distance_unoptimized_[int](*args)
    elif np.issubdtype(reference_timing.dtype, np.unsignedinteger):
        return time_constrained_levenshtein_distance_unoptimized_[uint](*args)
    elif np.issubdtype(reference_timing.dtype, np.floating):
        return time_constrained_levenshtein_distance_unoptimized_[double](*args)
    else:
        raise TypeError(reference_timing.dtype)

def time_constrained_levenshtein_distance_with_alignment(
        reference,  # list[int]
        hypothesis,  # list[int]
        reference_timing,  # list[tuple[int, int]]
        hypothesis_timing,  # list[tuple[int, int]]
        cost_del=1,
        cost_ins=1,
        cost_sub=1,
        cost_cor=0,
        eps='*',
):
    reference, hypothesis, reference_timing, hypothesis_timing = _validate_inputs(reference, hypothesis,
                                                                                  reference_timing, hypothesis_timing)
    if len(reference) == 0:
        return {
            'total': len(hypothesis),
            'alignment': [(eps, h) for h in hypothesis],
            'correct': 0,
            'insertions': len(hypothesis) * cost_ins,
            'deletions': 0,
            'substitutions': 0,
        }
    if len(hypothesis) == 0:
        return {
            'total': len(reference),
            'alignment': [(r, eps) for r in reference],
            'correct': 0,
            'insertions': 0,
            'deletions': len(reference) * cost_del,
            'substitutions': 0,
        }

    assert eps not in reference and eps not in hypothesis, (eps, reference, hypothesis)

    int2sym = dict(enumerate(sorted(set(reference) | set(hypothesis) | set([eps]))))
    sym2int = {v: k for k, v in int2sym.items()}
    reference = [sym2int[a_] for a_ in reference]
    hypothesis = [sym2int[b_] for b_ in hypothesis]
    eps = sym2int[eps]

    # Cython for some reason doesn't allow *args here
    if np.issubdtype(reference_timing.dtype, np.signedinteger):
        statistics = time_constrained_levenshtein_distance_with_alignment_[int](
            reference, hypothesis,
            reference_timing,
            hypothesis_timing,
            cost_del,
            cost_ins,
            cost_sub,
            cost_cor,
            eps
        )
    elif np.issubdtype(reference_timing.dtype, np.unsignedinteger):
        statistics = time_constrained_levenshtein_distance_with_alignment_[uint](
            reference, hypothesis,
            reference_timing,
            hypothesis_timing,
            cost_del,
            cost_ins,
            cost_sub,
            cost_cor,
            eps
        )
    elif np.issubdtype(reference_timing.dtype, np.floating):
        statistics = time_constrained_levenshtein_distance_with_alignment_[double](
            reference, hypothesis,
            reference_timing,
            hypothesis_timing,
            cost_del,
            cost_ins,
            cost_sub,
            cost_cor,
            eps
        )
    else:
        raise TypeError(reference_timing.dtype)

    statistics['alignment'] = [
        (int2sym[e[0]], int2sym[e[1]])
        for e in statistics['alignment']
    ]

    return statistics
