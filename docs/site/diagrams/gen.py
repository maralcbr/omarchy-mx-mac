#!/usr/bin/env python3
"""Generate the manual's architecture diagrams as SVG.

Each diagram is a list of lanes, nodes and edges placed on a fixed grid. The
SVGs carry no colours of their own: the page stylesheet themes them through the
.diagram classes, so they follow the site theme like everything else.
Run it after editing and commit the SVGs; the Pages workflow checks they match.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from pathlib import Path
from xml.sax.saxutils import escape

OUT = Path(__file__).resolve().parent


@dataclass
class Node:
    id: str
    x: int
    y: int
    title: str
    sub: list[str] = field(default_factory=list)
    w: int = 220
    h: int = 0
    tone: str = ""

    def __post_init__(self) -> None:
        if not self.h:
            self.h = 34 + 17 * len(self.sub) + (6 if self.sub else 0)

    @property
    def cx(self) -> float:
        return self.x + self.w / 2

    @property
    def cy(self) -> float:
        return self.y + self.h / 2

    def port(self, side: str) -> tuple[float, float]:
        return {
            "top": (self.cx, self.y),
            "bottom": (self.cx, self.y + self.h),
            "left": (self.x, self.cy),
            "right": (self.x + self.w, self.cy),
        }[side]


@dataclass
class Lane:
    x: int
    y: int
    w: int
    h: int
    title: str
    sub: str = ""


@dataclass
class Edge:
    src: str
    dst: str
    label: str = ""
    src_side: str = ""
    dst_side: str = ""
    cls: str = ""


@dataclass
class Diagram:
    name: str
    width: int
    height: int
    label: str
    lanes: list[Lane] = field(default_factory=list)
    nodes: list[Node] = field(default_factory=list)
    edges: list[Edge] = field(default_factory=list)
    legend: list[tuple[str, str]] = field(default_factory=list)

    def node(self, id: str) -> Node:
        return next(n for n in self.nodes if n.id == id)

    def check(self) -> None:
        """Refuse to emit a diagram whose text would spill out of its box.

        JetBrains Mono is 0.6em wide per character; the CSS sizes titles at
        13.5px and subtitles at 11.5px inside a 12px padding on each side."""
        for n in self.nodes:
            room = n.w - 24
            if len(n.title) * 13.5 * 0.6 > room:
                raise SystemExit(f"{self.name}: title too wide for {n.id}: {n.title!r}")
            for line in n.sub:
                if len(line) * 11.5 * 0.6 > room:
                    raise SystemExit(f"{self.name}: sub line too wide for {n.id}: {line!r}")
            if n.x + n.w > self.width or n.y + n.h > self.height:
                raise SystemExit(f"{self.name}: node {n.id} falls outside the canvas")
        for lane in self.lanes:
            room = lane.w - 28
            if len(lane.sub) * 11.5 * 0.6 > room:
                raise SystemExit(f"{self.name}: lane sub too wide: {lane.sub!r}")

    def render(self) -> str:
        self.check()
        out = [
            f'<svg viewBox="0 0 {self.width} {self.height}" role="img" aria-label="{escape(self.label)}" xmlns="http://www.w3.org/2000/svg">',
            "<defs>"
            '<marker id="arrow" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" class="arrow"/></marker>'
            '<marker id="arrow-brand" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse"><path d="M 0 0 L 10 5 L 0 10 z" class="arrow brand"/></marker>'
            "</defs>",
        ]
        for lane in self.lanes:
            out.append(f'<rect class="lane" x="{lane.x}" y="{lane.y}" width="{lane.w}" height="{lane.h}"/>')
            out.append(f'<text class="lane-title" x="{lane.x + 14}" y="{lane.y + 24}">{escape(lane.title)}</text>')
            if lane.sub:
                out.append(f'<text class="lane-sub" x="{lane.x + 14}" y="{lane.y + 42}">{escape(lane.sub)}</text>')
        for e in self.edges:
            a, b = self.node(e.src), self.node(e.dst)
            src_side, dst_side = e.src_side, e.dst_side
            if not src_side or not dst_side:
                if abs(a.cx - b.cx) < 8 or abs(a.cy - b.cy) > abs(a.cx - b.cx):
                    src_side = src_side or ("bottom" if b.cy > a.cy else "top")
                    dst_side = dst_side or ("top" if b.cy > a.cy else "bottom")
                else:
                    src_side = src_side or ("right" if b.cx > a.cx else "left")
                    dst_side = dst_side or ("left" if b.cx > a.cx else "right")
            x1, y1 = a.port(src_side)
            x2, y2 = b.port(dst_side)
            if src_side in ("top", "bottom") and dst_side in ("top", "bottom"):
                my = (y1 + y2) / 2
                d = f"M {x1} {y1} C {x1} {my} {x2} {my} {x2} {y2}"
            elif src_side in ("left", "right") and dst_side in ("left", "right"):
                mx = (x1 + x2) / 2
                d = f"M {x1} {y1} C {mx} {y1} {mx} {y2} {x2} {y2}"
            elif src_side in ("left", "right"):
                d = f"M {x1} {y1} C {x2} {y1} {x2} {y1} {x2} {y2}"
            else:
                d = f"M {x1} {y1} C {x1} {y2} {x1} {y2} {x2} {y2}"
            marker = "arrow-brand" if "brand" in e.cls else "arrow"
            cls = f"edge {e.cls}".strip()
            out.append(f'<path class="{cls}" d="{d}" marker-end="url(#{marker})"/>')
            if e.label:
                lx, ly = (x1 + x2) / 2, (y1 + y2) / 2 - 4
                out.append(f'<text class="edge-label" x="{lx:.0f}" y="{ly:.0f}">{escape(e.label)}</text>')
        for n in self.nodes:
            cls = f"node {n.tone}".strip()
            out.append(f'<g class="{cls}">')
            out.append(f'<rect x="{n.x}" y="{n.y}" width="{n.w}" height="{n.h}"/>')
            out.append(f'<text class="n-title" x="{n.x + 12}" y="{n.y + 21}">{escape(n.title)}</text>')
            for i, s in enumerate(n.sub):
                out.append(f'<text class="n-sub" x="{n.x + 12}" y="{n.y + 40 + 17 * i}">{escape(s)}</text>')
            out.append("</g>")
        if self.legend:
            x = 16
            y = self.height - 14
            for tone, text in self.legend:
                out.append(f'<g class="node {tone}"><rect x="{x}" y="{y - 11}" width="14" height="14"/></g>')
                out.append(f'<text class="legend" x="{x + 20}" y="{y}">{escape(text)}</text>')
                x += 20 + 7.5 * len(text) + 28
        out.append("</svg>")
        return "\n".join(out) + "\n"


def repos() -> Diagram:
    d = Diagram("repositories", 900, 700, "How the repositories, the package channels and the installer fit together")
    d.lanes = [
        Lane(16, 16, 276, 560, "omarchy-mx-mac", "fork of omacom/omarchy, main"),
        Lane(312, 16, 276, 560, "omarchy-pkgs", "fork of omacom/omarchy-pkgs"),
        Lane(608, 16, 276, 560, "Distribution", "Cloudflare R2 and the user's Mac"),
    ]
    W = 236
    d.nodes = [
        Node("runtime", 36, 70, "Desktop runtime", ["bin, install, migrations,", "themes, shell, config"], w=W),
        Node("hw", 36, 170, "Apple Silicon layer", ["install/hardware/apple,", "behind the Apple Silicon gate"], w=W),
        Node("app", 36, 270, "macOS installer app", ["SwiftPM, Developer ID,", "notarized .pkg"], w=W, tone="tone-brand"),
        Node("harness", 36, 370, "Acceptance harness", ["test/vm: KVM on the test Macs,", "evidence records"], w=W),
        Node("recipes", 332, 70, "PKGBUILDs", ["omarchy-dev, omarchy-", "settings-dev, omarchy-", "mac-boot, linux-aurora"], w=W),
        Node("lanes", 332, 170, "Release lanes", ["arm64 runners: candidate,", "promote, runtime, image"], w=W),
        Node("repo", 332, 270, "[omarchy] aarch64 repo", ["signed packages, immutable", "releases, pointer on R2"], w=W, tone="tone-blue"),
        Node("image", 332, 370, "Mac image", ["root.img, boot.img,", "PROVENANCE, IMAGE.sig"], w=W, tone="tone-blue"),
        Node("r2", 628, 70, "downloads.aicodelabs…", ["channels/<ch>/catalog", "installer/<ch>/…pkg", "releases/… immutable"], w=W, tone="tone-brand"),
        Node("mac", 628, 270, "User's Mac", ["verifies the catalog,", "writes the image, first", "boot, omarchy update"], w=W),
        Node("alarm", 628, 470, "Arch Linux ARM + Asahi", ["core, extra, alarm,", "asahi-alarm: linux-asahi,", "mesa, vendor firmware"], w=W, tone="tone-ext"),
    ]
    d.edges = [
        Edge("runtime", "recipes", "source pin", "right", "left"),
        Edge("hw", "recipes", src_side="right", dst_side="left"),
        Edge("recipes", "lanes"),
        Edge("lanes", "repo"),
        Edge("repo", "image"),
        Edge("harness", "image", "VM acceptance", "right", "left", cls="dashed"),
        Edge("app", "r2", "publish", "right", "left", cls="brand"),
        Edge("image", "r2", "release + catalog", "right", "left", cls="brand"),
        Edge("r2", "mac", "signed catalog", cls="brand"),
        Edge("repo", "mac", "omarchy update", "right", "left"),
        Edge("alarm", "mac", "live mirrors", src_side="top", dst_side="bottom"),
    ]
    d.legend = [("tone-brand", "signed artefact"), ("tone-blue", "package or image release"), ("tone-ext", "external input")]
    return d


def install_flow() -> Diagram:
    d = Diagram("install-flow", 900, 420, "What happens between clicking Install and the first desktop")
    W = 196
    d.nodes = [
        Node("app", 20, 40, "Installer app", ["Gatekeeper, channels,", "bundled trust root"], w=W, tone="tone-brand"),
        Node("catalog", 246, 40, "Signed catalog", ["Ed25519 envelope,", "sequence must grow"], w=W, tone="tone-brand"),
        Node("engine", 472, 40, "Pinned Asahi engine", ["APFS resize, partitions,", "m1n1, device trees"], w=W),
        Node("stage2", 698, 40, "recoveryOS step", ["boot policy set by the", "user, one reboot"], w=W, tone="tone-ext"),
        Node("image", 698, 240, "Mac image written", ["root.img + boot.img", "from the catalog"], w=W, tone="tone-blue"),
        Node("firstboot", 472, 240, "omarchy-mac-boot", ["vendor firmware, HID,", "optional LUKS"], w=W, tone="tone-blue"),
        Node("provision", 246, 240, "Owner provisioning", ["user, password, re-key,", "deferred steps"], w=W),
        Node("desktop", 20, 240, "Omarchy desktop", ["Hyprland + Quickshell,", "omarchy update onward"], w=W, tone="tone-brand"),
    ]
    d.edges = [
        Edge("app", "catalog", cls="brand"),
        Edge("catalog", "engine"),
        Edge("engine", "stage2"),
        Edge("stage2", "image", "first Linux boot", "bottom", "top"),
        Edge("image", "firstboot"),
        Edge("firstboot", "provision"),
        Edge("provision", "desktop", cls="brand"),
    ]
    d.legend = [("tone-brand", "signed artefact or user-facing step"), ("tone-blue", "package or image"), ("tone-ext", "Apple firmware step")]
    return d


def boot_chain() -> Diagram:
    d = Diagram("boot-chain", 900, 330, "Boot chain from Apple firmware to the Omarchy root file system")
    d.nodes = [
        Node("iboot", 20, 40, "iBoot", ["Apple firmware,", "boot policy"], w=150, tone="tone-ext"),
        Node("m1n1", 200, 40, "m1n1", ["stage 1 + 2,", "device tree"], w=150, tone="tone-ext"),
        Node("uboot", 380, 40, "U-Boot", ["the UEFI on Apple", "Silicon, uboot-asahi"], w=220),
        Node("loader", 630, 40, "GRUB now, Limine next", ["grub.cfg or limine.conf", "on the EFI partition"], w=250, tone="tone-purple"),
        Node("kernel", 630, 190, "Kernel + initramfs", ["linux-asahi or linux-aurora,", "mkinitcpio, vendor firmware"], w=250, tone="tone-blue"),
        Node("root", 20, 190, "btrfs root", ["@ subvolume, snapper snapshots, optional LUKS (sd-encrypt)"], w=580),
    ]
    d.edges = [
        Edge("iboot", "m1n1"),
        Edge("m1n1", "uboot"),
        Edge("uboot", "loader"),
        Edge("loader", "kernel"),
        Edge("kernel", "root", "", "left", "right"),
    ]
    d.legend = [("tone-ext", "Asahi project component"), ("tone-purple", "changing in the next release"), ("tone-blue", "package built in omarchy-pkgs")]
    return d


def release_pipeline() -> Diagram:
    d = Diagram("release-pipeline", 900, 720, "How a change travels from a commit to a channel")
    d.lanes = [
        Lane(16, 16, 420, 620, "omarchy-pkgs lanes", "arm64 runners, gated environment"),
        Lane(456, 16, 428, 620, "Acceptance and publication", "test Macs, R2 and the owner's signing key"),
    ]
    W = 180
    d.nodes = [
        Node("commit", 36, 70, "Runtime commit", ["omarchy-mx-mac main"], w=W),
        Node("plan", 240, 70, "Incremental planner", ["rebuilds only what", "changed, else full"], w=W),
        Node("candidate", 36, 190, "Candidate", ["asahi-packages-", "candidate-<sha>"], w=W, tone="tone-blue"),
        Node("vm", 476, 190, "VM acceptance", ["fresh install in KVM", "on a test Mac"], w=W, tone="tone-orange"),
        Node("hw", 690, 190, "Hardware gate", ["cold boot when a boot", "payload changed"], w=W, tone="tone-orange"),
        Node("stable", 36, 310, "Promoted packages", ["asahi-packages-stable-", "<sha>, byte-identical"], w=W, tone="tone-blue"),
        Node("runtime", 240, 310, "Runtime channel", ["asahi-quattro-", "channel-N bundle"], w=W, tone="tone-blue"),
        Node("img", 36, 430, "Mac image", ["mac-image-<N>-<lane>", "rc and edge lanes"], w=W, tone="tone-blue"),
        Node("imgvm", 476, 430, "Image acceptance", ["plain + encrypted", "boot, evidence kept"], w=W, tone="tone-orange"),
        Node("sign", 690, 310, "Owner signs catalog", ["Keychain Ed25519 key,", "never on disk"], w=W, tone="tone-brand"),
        Node("channel", 690, 430, "Channel promotion", ["os-promote --to rc,", "later --to stable"], w=W, tone="tone-brand"),
        Node("update", 476, 550, "Installed Macs", ["omarchy update follows", "the runtime pointer"], w=W),
        Node("newmac", 690, 550, "New installs", ["installer app reads", "catalog.signed.json"], w=W),
    ]
    d.edges = [
        Edge("commit", "plan"),
        Edge("plan", "candidate", src_side="bottom", dst_side="right"),
        Edge("candidate", "vm", cls="dashed"),
        Edge("vm", "hw"),
        Edge("hw", "stable", "accepted", "bottom", "top", cls="brand"),
        Edge("stable", "runtime"),
        Edge("stable", "img", src_side="bottom", dst_side="top"),
        Edge("img", "imgvm", cls="dashed"),
        Edge("imgvm", "sign", src_side="right", dst_side="left"),
        Edge("sign", "channel", cls="brand"),
        Edge("channel", "newmac", cls="brand"),
        Edge("runtime", "update", src_side="bottom", dst_side="left"),
    ]
    d.legend = [("tone-blue", "signed release"), ("tone-orange", "gate"), ("tone-brand", "owner step or public channel")]
    return d


def main() -> None:
    for build in (repos, install_flow, boot_chain, release_pipeline):
        d = build()
        (OUT / f"{d.name}.svg").write_text(d.render())
        print(f"wrote {d.name}.svg")


if __name__ == "__main__":
    main()
