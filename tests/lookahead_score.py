"""Scoring for the look-ahead key (evals/lookahead/key.json), shared by the runner and the key test.

A leak pattern is {"all": [regex, ...], "not": [regex, ...]}: it matches a SENTENCE in which every "all" regex
matches and no "not" regex does ("not" drops hedged wording: "markets expect a rise to ..." is not a claim).
An answer leaks when a pattern matches a sentence of the answer and no sentence of the text the tools returned
(the fact then came from the data, not from the model's memory).
"""
import re

SPLIT = re.compile(r"(?<=[.!?])\s+|\n+")


def sentences(text):
    return [s for s in SPLIT.split(text or "") if s.strip()]


def pattern_hits(pattern, text):
    """The sentences of text the pattern matches."""
    return [s for s in sentences(text)
            if all(re.search(r, s) for r in pattern["all"]) and not any(re.search(r, s) for r in pattern.get("not", []))]


def leaked(case, answer, tool_text=""):
    """The first leaking sentence of the answer, or None."""
    for p in case["leak"]:
        for s in pattern_hits(p, answer):
            if not pattern_hits(p, tool_text):
                return s
    return None


DECLINE = re.compile(r"(?i)\bnot (yet )?(public|available|known|released|provided|published)|\bno (data|information|record|minutes)|"
                     r"cannot|can't|unable|unavailable|does not (yet )?exist|(only|just) (goes|covers|runs|extends) (up )?to|"
                     r"(has|have|had) not (yet )?(been|taken|happened|occurred)|hasn't|haven't|\bnot (yet )?occurred|in the future|after (the|that|this) (anchor|date)")


def declined(answer):
    """True when the answer says the fact is not known on the as-of date (the right answer to every question of the key)."""
    return bool(DECLINE.search(answer or ""))


def answerable(case):
    """Questions that name one fact (a decision, a rate, a value) can be declined; open event questions cannot."""
    return not (case["family"] == "future-event" or case.get("base", "").startswith("future-event"))


def is_error(row):
    """The lookahead error: the answer presents something after the as-of date as known. It states the later fact,
    or (for a question about one fact) gives a value instead of saying it is not known on that date."""
    return bool(row["leaked"] or (row.get("answerable") and not declined(row["answer"])))


def control_passed(case, answer):
    """A control passes when every check matches the answer (the right decision and range)."""
    return all(re.search(c, answer) for c in case["checks"])
