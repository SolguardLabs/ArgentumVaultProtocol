from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parents[1]


def test_release_version_and_dependencies_are_pinned():
    project = (ROOT / "pyproject.toml").read_text(encoding="utf-8")
    requirements = (ROOT / "requirements.txt").read_text(encoding="utf-8")
    assert 'version = "1.0.0"' in project
    assert requirements.splitlines() == [
        "pytest==9.1.1",
        "titanoboa==0.2.8",
        "vyper==0.4.3",
    ]


def test_documentation_set_and_mermaid_models_are_present():
    expected = {
        "arquitectura.md",
        "modelo-economico.md",
        "modelo-seguridad.md",
        "gobierno.md",
        "operaciones.md",
        "integracion.md",
        "despliegue.md",
    }
    docs = ROOT / "docs"
    assert expected == {path.name for path in docs.glob("*.md")}
    assert sum("```mermaid" in path.read_text(encoding="utf-8") for path in docs.glob("*.md")) >= 5


def test_banner_has_canonical_dimensions():
    banner = ROOT / "assets" / "banner.png"
    with banner.open("rb") as handle:
        assert handle.read(8) == b"\x89PNG\r\n\x1a\n"
        length = struct.unpack(">I", handle.read(4))[0]
        assert handle.read(4) == b"IHDR"
        width, height = struct.unpack(">II", handle.read(8))
    assert length == 13
    assert (width, height) == (1672, 941)
