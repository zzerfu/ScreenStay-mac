from PIL import Image, ImageDraw, ImageFont, ImageFilter
import math
def hexc(h): return tuple(int(h[i:i+2],16) for i in (1,3,5))
def make(s, path):
    W,H=660*s,400*s
    im=Image.new("RGB",(W,H),hexc("#F8F9F5"))
    # grass slopes
    lay=Image.new("RGBA",(W,H),(0,0,0,0)); d=ImageDraw.Draw(lay)
    pts=[(x, H-0.29*H+ 18*s*math.sin(x/W*math.pi*1.3+0.4)) for x in range(0,W+1,4)]
    d.polygon(pts+[(W,H),(0,H)],fill=hexc("#EAF1E9")+(255,))
    pts2=[(x, H-0.17*H+ 12*s*math.sin(x/W*math.pi*2.1+1.6)) for x in range(0,W+1,4)]
    d.polygon(pts2+[(W,H),(0,H)],fill=hexc("#DCE4DC")+(150,))
    im.paste(lay,(0,0),lay)
    d=ImageDraw.Draw(im)
    # pads
    for cx in (180,480):
        r=80*s; d.ellipse([cx*s-r,200*s-r,cx*s+r,200*s+r],fill=hexc("#EAF1E9"),outline=hexc("#DCE4DC"),width=s)
    # chevrons
    for off in (-14,6):
        x=(330+off)*s; y=200*s; h=8*s
        d.line([(x,y-h),(x+8*s,y),(x,y+h)],fill=hexc("#90B59B"),width=3*s,joint="curve")
    sans="/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
    reg="/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
    f=ImageFont.truetype(sans,22*s); d.text((330*s,52*s),"ScreenStay",font=f,fill=hexc("#39745E"),anchor="mm")
    d.ellipse([ (330-72)*s-4*s,52*s-3*s,(330-72)*s+2*s,52*s+3*s],fill=hexc("#39745E"))
    f2=ImageFont.truetype(reg,14*s); d.text((330*s,312*s),"拖到 Applications 即可安装",font=f2,fill=hexc("#65766E"),anchor="mm")
    im.save(path,dpi=(72*s,72*s))
make(1,"dmg-background.png"); make(2,"dmg-background@2x.png")
