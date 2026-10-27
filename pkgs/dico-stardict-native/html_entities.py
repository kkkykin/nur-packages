"""Generate HTML entity tables at build time; the module has no Python runtime."""

import html
from html.entities import html5
import sys


def c_string(value):
    return '"' + ''.join(f'\\{byte:03o}' for byte in value.encode('utf-8')) + '"'


with open(sys.argv[1], 'w', encoding='ascii') as output:
    output.write('static const struct html_entity { const char *name, *value; } html_entities[] = {\n')
    for name, value in sorted(html5.items()):
        output.write(f'    {{ "{name}", {c_string(value)} }},\n')
    output.write('};\nstatic const char *html_numeric_controls[] = {\n')
    for value in range(160):
        output.write(f'    {c_string(html.unescape(f"&#{value};"))},\n')
    output.write('};\n')
