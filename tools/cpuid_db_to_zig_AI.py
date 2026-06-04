import re
from collections import defaultdict

STRUCT_RE = re.compile(r"struct\s+(\w+)\s*\{")
REGION_RE = re.compile(r"//\s*(eax|ebx|ecx|edx)\b")

BITFIELD_RE = re.compile(
    r"(?:(?P<name>[a-zA-Z0-9_]+)\s*:\s*(?P<bits>\d+)|:\s*(?P<anon>\d+))"
)

def parse_region(lines):
    fields = []
    pending_comment = None
    reserved_counter = 0

    for raw in lines:
        line = raw.strip().rstrip(",")

        if not line:
            continue

        # standalone comment line → store for next field
        if line.startswith("//"):
            pending_comment = line[2:].strip()
            continue

        m = BITFIELD_RE.search(line)
        if not m:
            continue

        bits = int(m.group("bits") or m.group("anon"))
        name = m.group("name")

        # inline comment override if present
        inline_comment = None
        if "//" in line:
            parts = line.split("//", 1)
            line = parts[0]
            inline_comment = parts[1].strip()

        comment = inline_comment or pending_comment
        pending_comment = None

        if not name:
            name = f"reserved_{reserved_counter}"
            reserved_counter += 1
            if not comment:
                comment = "Reserved"

        fields.append((name, bits, comment))

    return fields


def convert(c_code: str) -> str:
    lines = c_code.splitlines()
    i = 0
    out = []

    while i < len(lines):
        line = lines[i]

        struct_match = STRUCT_RE.search(line)
        if not struct_match:
            i += 1
            continue

        struct_name = struct_match.group(1)
        out.append(f"pub const {struct_name} = packed struct {{")

        i += 1
        buffer = defaultdict(list)
        current_region = None

        while i < len(lines) and "};" not in lines[i]:
            line = lines[i]

            region_match = REGION_RE.match(line.strip())
            if region_match:
                current_region = region_match.group(1)
                i += 1
                continue

            if current_region:
                buffer[current_region].append(line)

            i += 1

        for region in ["eax", "ebx", "ecx", "edx"]:
            if region not in buffer:
                continue

            fields = parse_region(buffer[region])

            out.append(f"    {region}: packed struct(u32) {{")
            for name, bits, comment in fields:
                if comment:
                    out.append(f"        {name}: u{bits}, // {comment}")
                else:
                    out.append(f"        {name}: u{bits},")
            out.append("    },\n")

        out.append("};")
        i += 1

    return "\n".join(out)


if __name__ == "__main__":
    with open("input.c", "r") as f:
        print(convert(f.read()))