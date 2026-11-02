#!/usr/bin/env python3
"""Regenerate the synthetic CC0 video EPUB. Requires ffmpeg; never needed at runtime."""
from pathlib import Path
import subprocess
import tempfile
import zipfile

root = Path(__file__).resolve().parents[1]
output = root / "Example/Shared/Sample eBooks/Embedded Video.epub"
with tempfile.TemporaryDirectory() as directory:
    video = Path(directory) / "demo.mp4"
    poster = Path(directory) / "poster.jpg"
    subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc2=size=320x180:rate=24",
                    "-f", "lavfi", "-i", "sine=frequency=440:sample_rate=44100", "-t", "8",
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-b:v", "100k", "-g", "24",
                    "-c:a", "aac", "-b:a", "32k", "-movflags", "+faststart", str(video)], check=True)
    subprocess.run(["ffmpeg", "-v", "error", "-i", str(video), "-frames:v", "1", str(poster)], check=True)
    def chapter(title, inline, source):
        attribute = ' playsinline="playsinline"' if inline else ""
        return f'''<?xml version="1.0" encoding="utf-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>{title}</title>
<meta name="viewport" content="width=device-width, initial-scale=1"/></head><body>
<h1>{title}</h1><p>Tap Play. Seek near the end, enter and leave full screen, then turn the page.</p>
<video id="demo" controls="controls"{attribute} preload="metadata" width="320" height="180"
 poster="../Images/poster.jpg" style="display:block;width:100%;height:auto;">
<source src="../Video/{source}" type="video/mp4"/><p>Video playback is unavailable.</p></video>
<p>This eight-second synthetic clip shows moving colour bars with a quiet 440 Hz tone.</p>
<p>The inline chapter uses a stored ZIP entry; the full-screen chapter uses Deflate.</p>
<a href="{'fullscreen' if inline else 'inline'}.xhtml">Other playback mode</a>
<div style="height:120vh;"></div><p>Scrolling here should pause the video.</p></body></html>'''
    files = {
        "META-INF/container.xml": '''<?xml version="1.0"?><container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0"><rootfiles><rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/></rootfiles></container>''',
        "EPUB/package.opf": '''<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="book-id"><metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
<dc:identifier id="book-id">urn:folio:embedded-video</dc:identifier><dc:title>Embedded Video</dc:title><dc:creator>FolioReaderKit</dc:creator><dc:language>en</dc:language><dc:rights>CC0: synthetic test media, no third-party content.</dc:rights><meta property="dcterms:modified">2026-11-02T00:00:00Z</meta></metadata><manifest>
<item id="inline" href="Text/inline.xhtml" media-type="application/xhtml+xml"/>
<item id="fullscreen" href="Text/fullscreen.xhtml" media-type="application/xhtml+xml"/>
<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
<item id="video" href="Video/demo.mp4" media-type="video/mp4"/>
<item id="compressed" href="Video/demo-deflated.mp4" media-type="video/mp4"/>
<item id="poster" href="Images/poster.jpg" media-type="image/jpeg" properties="cover-image"/>
</manifest><spine><itemref idref="inline"/><itemref idref="fullscreen"/></spine></package>''',
        "EPUB/nav.xhtml": '''<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>Contents</title></head><body><nav epub:type="toc"><h1>Contents</h1><ol><li><a href="Text/inline.xhtml">Inline video</a></li><li><a href="Text/fullscreen.xhtml">Full-screen video</a></li></ol></nav></body></html>''',
        "EPUB/Text/inline.xhtml": chapter("Inline video", True, "demo.mp4"),
        "EPUB/Text/fullscreen.xhtml": chapter("Full-screen video", False, "demo-deflated.mp4"),
        "EPUB/Images/poster.jpg": poster.read_bytes(),
        "EPUB/Video/demo.mp4": video.read_bytes(),
        "EPUB/Video/demo-deflated.mp4": video.read_bytes(),
    }
    with zipfile.ZipFile(output, "w") as archive:
        archive.writestr("mimetype", "application/epub+zip", compress_type=zipfile.ZIP_STORED)
        for name, data in files.items():
            archive.writestr(name, data, compress_type=(zipfile.ZIP_STORED if name.endswith("/demo.mp4") else zipfile.ZIP_DEFLATED))
print(output)
