"""Draw the authored raster reference for the Scout routing instrument."""

from PIL import Image, ImageDraw, ImageFilter

WIDTH, HEIGHT = 1400, 850
image = Image.new("RGB", (WIDTH, HEIGHT), "#dce3df")
draw = ImageDraw.Draw(image)

# A physical routing instrument, observed from a high front-left viewpoint.
shadow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
ImageDraw.Draw(shadow).ellipse((245, 564, 1180, 795), fill=(0, 0, 0, 150))
shadow = shadow.filter(ImageFilter.GaussianBlur(42))
image.paste(shadow, (0, 0), shadow)
draw = ImageDraw.Draw(image)
draw.polygon([(250, 325), (500, 459), (500, 692), (250, 557)], fill="#1d272a")
draw.polygon([(500, 459), (1150, 343), (1150, 575), (500, 692)], fill="#273336")
draw.polygon([(250, 325), (900, 210), (1150, 343), (500, 459)], fill="#465457")
draw.line([(250, 325), (900, 210), (1150, 343), (500, 459), (250, 325)], fill="#849395", width=5)
draw.line([(500, 459), (500, 692), (1150, 575), (1150, 343)], fill="#11191b", width=5)

# Three inset routing lanes converge on a raised copper selector.
for offset, color in [(0, "#73928e"), (48, "#73928e"), (96, "#d7a469")]:
    y = 328 + offset
    draw.line([(342, y), (565, y + 112), (800, y + 70)], fill="#182528", width=20)
    draw.line([(342, y - 2), (565, y + 110), (800, y + 68)], fill=color, width=5)

# Physical selector housing, with an elevated crown and visible sidewall.
draw.polygon([(789, 230), (857, 216), (900, 240), (900, 325), (832, 340), (789, 315)], fill="#ad744a")
draw.polygon([(789, 230), (857, 216), (900, 240), (832, 255)], fill="#e4b782")
draw.line([(832, 255), (832, 340)], fill="#74492f", width=5)
draw.polygon([(811, 263), (856, 255), (879, 268), (833, 278)], fill="#4c3830")

# Output channel and three cut-through sockets on the front wall.
draw.line([(902, 311), (1084, 354)], fill="#162326", width=23)
draw.line([(902, 307), (1084, 350)], fill="#d7a469", width=6)
for x, y in [(610, 518), (740, 495), (870, 472)]:
    draw.polygon([(x, y), (x + 72, y - 13), (x + 72, y + 44), (x, y + 57)], fill="#11191b")
    draw.line([(x + 10, y + 12), (x + 58, y + 3)], fill="#a5b8b3", width=4)
draw.polygon([(1026, 446), (1115, 430), (1115, 495), (1026, 511)], fill="#141d1e")
draw.line([(1044, 472), (1097, 462)], fill="#d7a469", width=7)

# Small fasteners make the object legible as a fabricated enclosure.
for x, y in [(290, 340), (887, 235), (1088, 350), (510, 440)]:
    draw.ellipse((x - 5, y - 5, x + 5, y + 5), fill="#c4cfcd")

image.save("design/prototypes/spatial/assets/routing-instrument-reference.png")
