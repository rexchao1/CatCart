"""Draw the embedded can label. Run with .venv/bin/python."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'art/models/food/label.png'
W,H=3072,600
im=Image.new('RGB',(W,H),'#00B8D0')
d=ImageDraw.Draw(im)
font_path='/System/Library/Fonts/Supplemental/Arial Bold.ttf'
def font(size): return ImageFont.truetype(font_path,size)
# Broad continuous white edges stay visible from every rotation.
d.rectangle((0,0,W,26),fill='#E9FFFF')
d.rectangle((0,H-27,W,H),fill='#E9FFFF')
for x in (0,W//2,W):
    d.text((x,107),'WET CAT FOOD',font=font(83),anchor='mm',fill='#07354C',stroke_width=0)
    # White salmon silhouette with a small navy eye and simple gill marks.
    y=300
    d.ellipse((x-184,y-94,x+133,y+94),fill='#FFFFFF')
    d.polygon([(x+95,y),(x+236,y-102),(x+224,y+102)],fill='#FFFFFF')
    d.polygon([(x-47,y-77),(x+23,y-134),(x+53,y-72)],fill='#FFFFFF')
    d.ellipse((x-143,y-29,x-121,y-7),fill='#07354C')
    d.arc((x-127,y-68,x-58,y+68),-74,74,fill='#00B8D0',width=10)
    d.line((x-29,y-45,x-8,y,x-29,y+45),fill='#00B8D0',width=11)
    d.line((x+29,y-43,x+50,y,x+29,y+43),fill='#00B8D0',width=11)
    d.text((x,491),'SALMON IN GRAVY',font=font(62),anchor='mm',fill='#07354C')
im.save(OUT)
print(OUT)
