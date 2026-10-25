#!/usr/bin/env python3
"""Reference implementation of WordCore's scheduling rules.

Mirrors `Sources/WordCore/Scheduler.swift`, `SessionBuilder.swift` and the
`StudyLog` part of `LearningState.swift`, and asserts the SAME expectations that
`Tests/CoreTests/*.swift` assert on the Swift side.

Running it proves the algorithm and the date arithmetic are what we think they
are, on a machine that cannot compile Swift:
    python tools/reference_scheduler.py
"""
from __future__ import annotations

from datetime import date, timedelta

EPOCH = date(1970, 1, 1)
INTERVALS = [1, 1, 2, 4, 7, 15, 30, 60, 120]
MAX_BOX = len(INTERVALS)

failures: list[str] = []


def check(label: str, actual, expected) -> None:
    ok = actual == expected
    print(f"{'ok  ' if ok else 'FAIL'} {label}: {actual!r}" + ("" if ok else f"  (expected {expected!r})"))
    if not ok:
        failures.append(label)


class Day:
    def __init__(self, raw: int):
        self.raw = raw

    @staticmethod
    def of(y: int, m: int, d: int) -> "Day":
        return Day((date(y, m, d) - EPOCH).days)

    def add(self, days: int) -> "Day":
        return Day(self.raw + days)

    def iso(self) -> str:
        return (EPOCH + timedelta(days=self.raw)).isoformat()

    def __eq__(self, other) -> bool:
        return isinstance(other, Day) and other.raw == self.raw

    def __lt__(self, other: "Day") -> bool:
        return self.raw < other.raw

    def __le__(self, other: "Day") -> bool:
        return self.raw <= other.raw

    def __gt__(self, other: "Day") -> bool:
        return self.raw > other.raw

    def __hash__(self) -> int:
        return self.raw

    def __repr__(self) -> str:
        return self.iso()


class Card:
    def __init__(self, box=0, due=None, reps=0, lapses=0, starred=False):
        self.box = box
        self.due = due
        self.reps = reps
        self.lapses = lapses
        self.starred = starred

    def __repr__(self) -> str:
        return f"Card(box={self.box}, due={self.due})"


def grade(state: Card, correct: bool, today: Day) -> Card:
    nxt = Card(state.box, state.due, state.reps + 1, state.lapses, state.starred)
    if correct:
        nxt.box = min(state.box + 1, MAX_BOX)
    else:
        nxt.box = 1
        nxt.lapses += 1
    nxt.due = today.add(INTERVALS[min(max(nxt.box - 1, 0), len(INTERVALS) - 1)])
    return nxt


def build_session(words, cards, today, daily_new, review_cap, new_done=0, review_done=0):
    fresh_budget = max(daily_new - new_done, 0)
    review_budget = max(review_cap - review_done, 0)

    fresh = []
    if fresh_budget > 0:
        for word in words:
            if len(fresh) >= fresh_budget:
                break
            card = cards.get(word)
            if card is not None and card.box != 0:
                continue
            fresh.append(word)

    reviews = []
    if review_budget > 0:
        due = []
        for word in words:
            card = cards.get(word)
            if card is None or card.box == 0 or card.due > today:
                continue
            due.append(word)
        due.sort(key=lambda w: (cards[w].due.raw, cards[w].box, w))
        reviews = due[:review_budget]

    return fresh + reviews


class StudyLog:
    def __init__(self):
        self.day = None
        self.new_count = 0
        self.review_count = 0
        self.streak = 0
        self.best = 0
        self.last = None

    def rollover(self, today: Day) -> None:
        if self.day == today:
            return
        self.day = today
        self.new_count = 0
        self.review_count = 0
        if self.last is not None and today.raw - self.last.raw > 1:
            self.streak = 0

    def touch(self, today: Day) -> None:
        if self.last == today:
            return
        if self.last is not None and today.raw - self.last.raw == 1:
            self.streak += 1
        else:
            self.streak = 1
        self.last = today
        self.best = max(self.best, self.streak)

    def display_streak(self, today: Day) -> int:
        if self.last is None:
            return 0
        return self.streak if today.raw - self.last.raw <= 1 else 0


def main() -> int:
    today = Day.of(2025, 1, 15)
    check("raw of 1970-01-01", Day.of(1970, 1, 1).raw, 0)
    check("raw of 2025-01-15", today.raw, 20103)
    check("2025-01-15 +1", today.add(1).iso(), "2025-01-16")
    check("2025-01-15 -1", today.add(-1).iso(), "2025-01-14")

    # Cross-DST arithmetic still moves exactly one calendar day.
    check("2024-03-10 +1 (US DST start)", Day.of(2024, 3, 10).add(1).iso(), "2024-03-11")
    check("2024-11-03 +1 (US DST end)", Day.of(2024, 11, 3).add(1).iso(), "2024-11-04")

    # Interval ladder: box 1 and 2 are both one day, then it widens.
    card = Card(box=0, due=today)
    ladder = []
    for _ in range(9):
        card = grade(card, True, today)
        ladder.append((card.box, card.due.iso()))
    check("correct ladder", ladder, [
        (1, "2025-01-16"),
        (2, "2025-01-16"),
        (3, "2025-01-17"),
        (4, "2025-01-19"),
        (5, "2025-01-22"),
        (6, "2025-01-30"),
        (7, "2025-02-14"),
        (8, "2025-03-16"),
        (9, "2025-05-15"),
    ])
    check("box is capped at MAX_BOX", card.box, MAX_BOX)

    lapsed = grade(Card(box=6, due=today, reps=6), False, today)
    check("miss resets to box 1", (lapsed.box, lapsed.due.iso(), lapsed.lapses), (1, "2025-01-16", 1))

    # Session composition: overdue / due today / not due / unseen.
    words = ["w1", "w2", "w3", "w4", "w5", "w6"]
    cards = {
        "w1": Card(box=2, due=today.add(-1)),
        "w2": Card(box=1, due=today.add(-3)),
        "w3": Card(box=1, due=today),
        "w4": Card(box=1, due=today.add(1)),
        "w5": Card(box=0, due=today),
    }
    check("session order", build_session(words, cards, today, 3, 60), ["w5", "w6", "w2", "w1", "w3"])
    check(
        "session with 2 new done",
        build_session(words, cards, today, 3, 60, new_done=2),
        ["w5", "w2", "w1", "w3"],
    )
    check(
        "session with review cap hit",
        build_session(words, cards, today, 3, 60, review_done=60),
        ["w5", "w6"],
    )
    check(
        "session with all new done",
        build_session(words, cards, today, 3, 60, new_done=3),
        ["w2", "w1", "w3"],
    )
    check("empty session when everything done", build_session(words, cards, today, 0, 0), [])
    check("not-due card stays out", "w4" in build_session(words, cards, today, 5, 60), False)

    # Streak rules.
    log = StudyLog()
    log.rollover(today)
    check("fresh log streak", log.streak, 0)

    log.touch(today)
    check("first study day", (log.streak, log.last.iso()), (1, "2025-01-15"))
    log.touch(today)
    check("touch twice in one day", log.streak, 1)

    log.rollover(today.add(1))
    log.touch(today.add(1))
    check("consecutive day", log.streak, 2)

    log.rollover(today.add(3))
    check("skip a day breaks streak", log.streak, 0)
    log.touch(today.add(3))
    check("restart after break", log.streak, 1)

    check("display streak same day", log.display_streak(today.add(3)), 1)
    check("display streak next day", log.display_streak(today.add(4)), 1)
    check("display streak two days later", log.display_streak(today.add(5)), 0)

    print()
    if failures:
        print(f"{len(failures)} FAILED: {failures}")
        return 1
    print("all reference checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
