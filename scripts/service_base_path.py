"""Set only an application's base path before startup; never print private config."""
import json
import os
from pathlib import Path
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ET


def configure(kind, filename, prefix):
    path = Path(filename)
    if kind == "jackett":
        config = json.loads(path.read_text()) if path.exists() else {}
        if config.get("BasePathOverride") == prefix:
            return
        config["BasePathOverride"] = prefix
        content = (json.dumps(config, indent=2) + "\n").encode()
    elif kind == "jellyfin":
        tree = ET.parse(path) if path.exists() else ET.ElementTree(ET.Element("NetworkConfiguration"))
        root = tree.getroot()
        if root.tag != "NetworkConfiguration":
            raise ValueError("Unexpected Jellyfin network configuration root")
        field = root.find("BaseUrl")
        if field is not None and field.text == prefix:
            return
        if field is None:
            field = ET.SubElement(root, "BaseUrl")
        field.text = prefix
        content = ET.tostring(root, encoding="utf-8", xml_declaration=True)
    else:
        raise ValueError("Unknown service")

    # Files remain outside the Nix store, in the service's existing private dir.
    backup = path.with_name(path.name + ".before-subpath")
    if path.exists() and not backup.exists():
        shutil.copyfile(path, backup)
        backup.chmod(0o600)
    fd, temporary = tempfile.mkstemp(prefix=".base-path-", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as target:
            target.write(content)
            target.flush()
            os.fsync(target.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    try:
        configure(*sys.argv[1:])
    except Exception:
        # Parse errors can contain source text. Don't put configuration in logs.
        sys.exit("Could not apply service base path; existing configuration was not replaced.")
