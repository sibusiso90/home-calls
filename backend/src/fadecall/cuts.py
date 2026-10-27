"""The cut catalog a client can pick from instead of sending a reference photo.

Muse Spark also suggests cuts from this list to suit the client's face, so every
id here is a valid suggestion. ``minutes`` is a typical home-call time; the quote
adjusts it for the client's own hair.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class Cut:
    id: str
    name: str
    description: str
    minutes: int
    styles: tuple[str, ...]

    def as_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "description": self.description,
            "minutes": self.minutes,
            "styles": list(self.styles),
        }


CUTS = [
    Cut(
        "mid-skin-fade-textured",
        "Mid skin fade with textured top",
        "Sides faded to the skin from the temple down, with length and texture left on top.",
        50,
        ("skin fade", "mid fade", "textured top"),
    ),
    Cut(
        "low-taper-lineup",
        "Low taper with line-up",
        "A gentle taper just above the ears and neck, finished with a sharp hairline.",
        40,
        ("taper", "line-up"),
    ),
    Cut(
        "high-fade-brush",
        "High skin fade with brush cut",
        "Skin up high on the sides and a short, even brush cut on top.",
        45,
        ("high fade", "skin fade", "brush cut"),
    ),
    Cut(
        "chiskop-beard",
        "Chiskop with beard line-up",
        "Clean shaven head with a shaped, lined-up beard.",
        30,
        ("chiskop", "beard trim", "line-up"),
    ),
    Cut(
        "drop-fade-waves",
        "Drop fade with waves",
        "A fade that drops behind the ear, short brushed top to show waves.",
        55,
        ("low fade", "waves"),
    ),
    Cut(
        "burst-fade-twists",
        "Burst fade with twists",
        "Fade curved around the ear with twists or sponge curls on top.",
        70,
        ("skin fade", "twists"),
    ),
    Cut(
        "buzz-cut",
        "Buzz cut",
        "One clipper length all over. Quick, low maintenance.",
        20,
        ("buzz cut",),
    ),
    Cut(
        "crew-cut",
        "Crew cut",
        "Short tapered sides with a little more length on top, neat and classic.",
        35,
        ("crew cut", "taper"),
    ),
    Cut(
        "afro-shape-up",
        "Afro shape-up",
        "Natural length kept, shaped round with a clean edge and line-up.",
        45,
        ("afro shape-up", "line-up"),
    ),
]
CUTS_BY_ID = {c.id: c for c in CUTS}
CUT_IDS = [c.id for c in CUTS]


def get_cut(cut_id: str | None) -> Cut | None:
    return CUTS_BY_ID.get(cut_id) if cut_id else None


def cut_photo_key(cut_id: str) -> str:
    """Storage key of an uploaded photo that replaces the cut's illustration."""
    return f"cuts/{cut_id}.jpg"
