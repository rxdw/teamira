# PDF export fonts

Used only by `KeepsakePdfService` (the Diary keepsake / Wrapped PDF
exports), so the exports carry the app's own type — Unbounded for
headings, Comfortaa for body/UI text, Caveat for handwritten
notes/captions — and work fully offline (posters are the only
network fetch left in that flow).

Each file here is a **static instance**, cut from Google Fonts'
variable source, then **subsetted** to Latin + Cyrillic + the
punctuation the service actually emits (em/en dash, curly quotes,
ellipsis, №, ×, middle dot, →, bullet). That keeps six weights under
~330 KB total instead of shipping full variable families.

| file                  | source family (Google Fonts, OFL) | instance |
|-----------------------|------------------------------------|----------|
| Unbounded-Bold.ttf    | Unbounded                          | wght 700 |
| Unbounded-Black.ttf   | Unbounded                          | wght 900 |
| Comfortaa-Regular.ttf | Comfortaa                          | wght 400 |
| Comfortaa-Bold.ttf    | Comfortaa                          | wght 700 |
| Caveat-Regular.ttf    | Caveat                             | wght 500 |
| Caveat-Bold.ttf       | Caveat                             | wght 700 |

## Regenerating

```
pip install fonttools --break-system-packages
```

```python
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer
from fontTools import subset

jobs = [
    ("Unbounded[wght].ttf", 700, "Unbounded-Bold.ttf"),
    ("Unbounded[wght].ttf", 900, "Unbounded-Black.ttf"),
    ("Comfortaa[wght].ttf", 400, "Comfortaa-Regular.ttf"),
    ("Comfortaa[wght].ttf", 700, "Comfortaa-Bold.ttf"),
    ("Caveat[wght].ttf", 500, "Caveat-Regular.ttf"),
    ("Caveat[wght].ttf", 700, "Caveat-Bold.ttf"),
]
uni = (
    list(range(0x20, 0x7F)) + list(range(0xA0, 0x100)) +
    list(range(0x400, 0x460)) +
    [0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x201E,
     0x2022, 0x2026, 0x2116, 0x2192, 0x00D7, 0x00B7, 0x2212]
)
for src, weight, out in jobs:
    f = instancer.instantiateVariableFont(TTFont(src), {"wght": weight})
    opts = subset.Options()
    opts.layout_features = ["kern"]
    opts.hinting = False
    s = subset.Subsetter(opts)
    s.populate(unicodes=uni)
    s.subset(f)
    f.save(out)
```

Source variable files come from
`https://github.com/google/fonts` (`ofl/unbounded`, `ofl/comfortaa`,
`ofl/caveat`) — all OFL-licensed, safe to bundle.

If the service ever needs a glyph outside this set (e.g. another
script), add its codepoints to `uni` above and re-run — a missing
glyph renders as `.notdef` (a blank box), not a crash.
