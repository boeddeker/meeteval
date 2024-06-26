# Time-Constrained minimum Permutation Word Error Rate (tcpWER)

The Time-Constrained minimum Permutation Word Error Rate (tcpWER) is similar to the cpWER, but uses temporal information to prevent matching words that are far apart temporally.
By this, we aim to enforce a certain level of accuracy of the temporal annotations.

The temporal constraint idea is similar (but not identical) to aslicte's `-time-prune` option.
It yields a significant speedup compared to the plain cpWER, and it has been used in asclite for exactly this reason.
When the parameters are chosen wrongly, the tcpWER can give a value that is significantly larger than its time-constraint-free version.
While such an optimization can be seen as an approximation used to improve the runtime costs, we here explicitly count temporal errors to account for (obvious) temporal diarization mistakes.   

## Goals of the tcpWER
The transcription system should be forced to provide rough temporal annotations (diarization) and should be penalized when its results become implausible compared to the reference. 
This leads us to following properties:

- The system should group segments that it thinks belong to the same speaker together (similar to cpWER).
- It should not be penalized when the system combines several words (e.g. an utterance) in one segment, but
- It should be penalized when it produces (too) long segments spanning multiple reference segments.
- It should not be penalized when the system provides more precise timing than the reference (e.g., by splitting in a pause or producing tighter bounds).
- The tcpWER is faster to compute than the cpWER.

## Pseudo-word-level annotations
To compute the matching, we need a temporal annotation (start and end time) for each word.
Often, detailed word-level temporal annotations are not available, either because annotating a reference is expensive or a system does not produce such detailed information.
We thus implement different strategies to infer "pseudo-word-level" timings from segment-level timings:

- `full_segment`: Copy the time annotation from the segment to every word within that segment
- `equidistant_intervals`: Divides the segment-level interval into number-of-words many equally sized intervals
- `euqidistant_points`: Places words as time-points (zero-length intervals) equally spaced in the segment
- `character_based`: Estimate word length from the number of characters in a word
- `character_based_points`: Same as `character_based`, but only use the center point of a word instead of the full time span

To achieve the goals mentioned above we use `character_based` as the default for the reference and `character_based_points` as the default for the hypothesis (system output).
We recommend the character-based approximation of word lengths because it is straightforward and more accurate than the equidistant approximation.

The system can exploit the following choices for the hypothesis:
- `full_segment`: The system can output a single segment and achieve the same result as cpWER (effectively ignoring the time constraint)
- `character_based` or `euqidistant_intervals`: The system can split off the first and last word of a segment and fill the gaps between segments with them. This improves the WER slightly.

See [the paper](https://arxiv.org/abs/2307.11394) for a more detailed discussion.

## Collar
We include a collar option `--collar` that is added to the hypothesis temporal annotations (adding it to the reference vs hypothesis is equivalent).
It specifies how much the system's (and pseudo-word-level annotation strategy's) prediction can differ from the ground truth annotation before it is counted as an error.
Due to how pseudo-word-level annotations are estimated for the segment-level annotations, the collar has to be relatively large (compared to typical values for DER computation).
It should be chosen so that small diarization errors (e.g., merging two utterances of the same speaker uttered without a pause into a single segment) are not penalized but larger errors (merging utterances that are tens of seconds apart) is penalized.
This depends on the data, but we found values in the range of 2-5s to work well on libri-CSS.
See [the paper](https://arxiv.org/abs/2307.11394) for a more detailed discussion.

## Using tcpWER

The tcpWER for all file formats supported by meeteval (see [here](../README.md#file-formats)) that provide the necessary information (transcripts and start and end times).
Most prominently, it supports SegLST (from the Chime challenges) and STM.
You can use any resolution for the begin and end times (e.g., seconds or samples), but make sure to adjust the collar accordingly (`5` or `80000` for 16kHz).
```shell
# SegLST
meeteval-wer tcpwer -h hyp.json -r ref.json --collar 5
# STM
meeteval-wer tcpwer -h hyp.stm -r ref.stm --collar 5
```

[^1]: Some annotations in LibriSpeech, for example, contain extraordinarily long pauses of a few seconds within one annotated utterance
