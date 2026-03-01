$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Drawing

Set-StrictMode -Version Latest

$Root = Split-Path -Parent $PSScriptRoot
$OutDir = $Root
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Force $OutDir | Out-Null }

$CanvasWidth = 1800
$CanvasHeight = 1050

function New-RoundRectPath {
  param(
    [System.Drawing.RectangleF]$Rect,
    [float]$Radius
  )
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $r = [Math]::Max(0.0, $Radius)
  $d = $r * 2.0
  if ($d -ge $Rect.Width) { $d = $Rect.Width - 1.0 }
  if ($d -ge $Rect.Height) { $d = $Rect.Height - 1.0 }

  $x = $Rect.X; $y = $Rect.Y; $rw = $Rect.Width; $rh = $Rect.Height
  $path.AddArc($x, $y, $d, $d, 180, 90) | Out-Null
  $path.AddArc($x + $rw - $d, $y, $d, $d, 270, 90) | Out-Null
  $path.AddArc($x + $rw - $d, $y + $rh - $d, $d, $d, 0, 90) | Out-Null
  $path.AddArc($x, $y + $rh - $d, $d, $d, 90, 90) | Out-Null
  $path.CloseFigure() | Out-Null
  return $path
}

function Color-Rgb {
  param([int]$R, [int]$G, [int]$B)
  return [System.Drawing.Color]::FromArgb(255, $R, $G, $B)
}

function Color-Rgba {
  param([int]$A, [int]$R, [int]$G, [int]$B)
  return [System.Drawing.Color]::FromArgb($A, $R, $G, $B)
}

function Draw-Shadow {
  param(
    [System.Drawing.Graphics]$G,
    [System.Drawing.RectangleF]$Rect,
    [float]$Radius,
    [int]$Layers = 12,
    [float]$OffsetX = 8.0,
    [float]$OffsetY = 10.0
  )
  if ($Rect -is [Array]) { $Rect = $Rect[0] }
  for ($i = 0; $i -lt $Layers; $i++) {
    $alpha = [Math]::Max(0, 55 - ($i * 4))
    $grow = 1.0 + ($i * 1.2)
    $r2 = New-Object System.Drawing.RectangleF -ArgumentList @(
      ($Rect.X + $OffsetX - $grow),
      ($Rect.Y + $OffsetY - $grow),
      ($Rect.Width + (2.0 * $grow)),
      ($Rect.Height + (2.0 * $grow))
    )
    $p = New-RoundRectPath -Rect $r2 -Radius ($Radius + $i * 0.8)
    $b = New-Object System.Drawing.SolidBrush (Color-Rgba -A $alpha -R 0 -G 0 -B 0)
    $G.FillPath($b, $p)
    $b.Dispose()
    $p.Dispose()
  }
}

function Draw-Card {
  param(
    [System.Drawing.Graphics]$G,
    [System.Drawing.RectangleF]$Rect,
    [string]$Title,
    [System.Drawing.Color]$Fill,
    [System.Drawing.Color]$Stroke,
    [System.Drawing.Color]$TitleFill
  )
  Draw-Shadow -G $G -Rect $Rect -Radius 18 -Layers 10 -OffsetX 10 -OffsetY 12

  $path = New-RoundRectPath -Rect $Rect -Radius 18
  $b = New-Object System.Drawing.SolidBrush $Fill
  $G.FillPath($b, $path)
  $b.Dispose()

  $p = New-Object System.Drawing.Pen $Stroke, 2.0
  $G.DrawPath($p, $path)
  $p.Dispose()
  $path.Dispose()

  $titleRect = New-Object System.Drawing.RectangleF($Rect.X, $Rect.Y, $Rect.Width, 54)
  $titlePath = New-RoundRectPath -Rect $titleRect -Radius 18
  $tb = New-Object System.Drawing.SolidBrush $TitleFill
  $G.FillPath($tb, $titlePath)
  $tb.Dispose()
  $titlePath.Dispose()

  $font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
  $brush = New-Object System.Drawing.SolidBrush (Color-Rgb 32 38 45)
  $G.DrawString($Title, $font, $brush, $Rect.X + 18, $Rect.Y + 14)
  $brush.Dispose()
  $font.Dispose()
}

function Draw-Sticker {
  param(
    [System.Drawing.Graphics]$G,
    [float]$X,
    [float]$Y,
    [string]$Text,
    [System.Drawing.Color]$Accent
  )
  $font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
  $sz = $G.MeasureString($Text, $font)
  $w = [Math]::Ceiling($sz.Width + 18)
  $h = [Math]::Ceiling($sz.Height + 10)
  $r = New-Object System.Drawing.RectangleF($X, $Y, $w, $h)

  Draw-Shadow -G $G -Rect $r -Radius 10 -Layers 6 -OffsetX 4 -OffsetY 5
  $path = New-RoundRectPath -Rect $r -Radius 10
  $fill = New-Object System.Drawing.SolidBrush (Color-Rgb 255 255 255)
  $G.FillPath($fill, $path)
  $fill.Dispose()

  $pen = New-Object System.Drawing.Pen (Color-Rgb 210 216 224), 1.0
  $G.DrawPath($pen, $path)
  $pen.Dispose()

  $accPen = New-Object System.Drawing.Pen $Accent, 4.0
  $G.DrawLine($accPen, $X + 10, $Y + 5, $X + 10, $Y + $h - 6)
  $accPen.Dispose()

  $textBrush = New-Object System.Drawing.SolidBrush (Color-Rgb 24 28 33)
  $G.DrawString($Text, $font, $textBrush, $X + 18, $Y + 5)
  $textBrush.Dispose()
  $font.Dispose()
  $path.Dispose()
}

function Draw-Wire {
  param(
    [System.Drawing.Graphics]$G,
    [System.Drawing.PointF]$A,
    [System.Drawing.PointF]$B,
    [System.Drawing.Color]$Color,
    [float]$Width = 7.5,
    [string]$Label = "",
    [System.Drawing.PointF]$LabelPos = ([System.Drawing.PointF]::new(0,0))
  )
  $outline = New-Object System.Drawing.Pen (Color-Rgba -A 170 -R 0 -G 0 -B 0), ($Width + 3.0)
  $outline.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $outline.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $G.DrawLine($outline, $A, $B)
  $outline.Dispose()

  $pen = New-Object System.Drawing.Pen $Color, $Width
  $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.EndCap = [System.Drawing.Drawing2D.LineCap]::Round
  $pen.CustomEndCap = New-Object System.Drawing.Drawing2D.AdjustableArrowCap(6, 6, $true)
  $G.DrawLine($pen, $A, $B)
  $pen.Dispose()

  $termFill = New-Object System.Drawing.SolidBrush (Color-Rgb 255 255 255)
  $termPen = New-Object System.Drawing.Pen (Color-Rgb 120 130 140), 2.0
  $G.FillEllipse($termFill, $A.X - 6, $A.Y - 6, 12, 12)
  $G.DrawEllipse($termPen, $A.X - 6, $A.Y - 6, 12, 12)
  $G.FillEllipse($termFill, $B.X - 6, $B.Y - 6, 12, 12)
  $G.DrawEllipse($termPen, $B.X - 6, $B.Y - 6, 12, 12)
  $termPen.Dispose()
  $termFill.Dispose()

  if ($Label -ne "") {
    Draw-Sticker -G $G -X $LabelPos.X -Y $LabelPos.Y -Text $Label -Accent $Color
  }
}

function Crop-AndPlace {
  param(
    [System.Drawing.Graphics]$G,
    [System.Drawing.Image]$Img,
    [System.Drawing.Rectangle]$Crop,
    [System.Drawing.RectangleF]$Dest,
    [float]$Radius = 18.0
  )
  $bmp = New-Object System.Drawing.Bitmap $Crop.Width, $Crop.Height
  $gg = [System.Drawing.Graphics]::FromImage($bmp)
  $gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $gg.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $gg.DrawImage($Img, (New-Object System.Drawing.Rectangle(0,0,$Crop.Width,$Crop.Height)), $Crop, [System.Drawing.GraphicsUnit]::Pixel)
  $gg.Dispose()

  Draw-Shadow -G $G -Rect $Dest -Radius $Radius -Layers 14 -OffsetX 12 -OffsetY 14

  $clipPath = New-RoundRectPath -Rect $Dest -Radius $Radius
  $state = $G.Save()
  $G.SetClip($clipPath)
  $G.DrawImage($bmp, $Dest)
  $G.Restore($state)

  $clipPath.Dispose()
  $bmp.Dispose()

  $borderPath = New-RoundRectPath -Rect $Dest -Radius $Radius
  $pen = New-Object System.Drawing.Pen (Color-Rgba -A 160 -R 40 -G 50 -B 60), 2.0
  $G.DrawPath($pen, $borderPath)
  $pen.Dispose()
  $borderPath.Dispose()
}

function New-Canvas {
  $bmp = New-Object System.Drawing.Bitmap 1800, 1050
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
  $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
  $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit

  $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
    (New-Object System.Drawing.RectangleF(0,0,1800,1050)),
    (Color-Rgb 248 250 253),
    (Color-Rgb 235 240 247),
    90.0
  )
  $g.FillRectangle($bg, 0, 0, 1800, 1050)
  $bg.Dispose()

  return @{ bmp = $bmp; g = $g }
}

function Draw-Header {
  param([System.Drawing.Graphics]$G, [string]$Title)
  $rect = New-Object System.Drawing.RectangleF(30, 22, 1740, 88)
  Draw-Shadow -G $G -Rect $rect -Radius 18 -Layers 8 -OffsetX 8 -OffsetY 10
  $path = New-RoundRectPath -Rect $rect -Radius 18
  $fill = New-Object System.Drawing.SolidBrush (Color-Rgb 245 247 250)
  $G.FillPath($fill, $path)
  $fill.Dispose()
  $pen = New-Object System.Drawing.Pen (Color-Rgb 180 190 204), 2.0
  $G.DrawPath($pen, $path)
  $pen.Dispose()
  $path.Dispose()

  $font = New-Object System.Drawing.Font("Segoe UI", 26, [System.Drawing.FontStyle]::Bold)
  $brush = New-Object System.Drawing.SolidBrush (Color-Rgb 28 33 39)
  $G.DrawString($Title, $font, $brush, 58, 46)
  $brush.Dispose()
  $font.Dispose()
}

function Draw-DomainBadge {
  param([System.Drawing.Graphics]$G, [float]$X, [float]$Y, [string]$Text, [System.Drawing.Color]$Color)
  $font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
  $sz = $G.MeasureString($Text, $font)
  $w = [Math]::Ceiling($sz.Width + 18)
  $h = [Math]::Ceiling($sz.Height + 10)
  $r = New-Object System.Drawing.RectangleF($X, $Y, $w, $h)
  Draw-Shadow -G $G -Rect $r -Radius 12 -Layers 6 -OffsetX 5 -OffsetY 6
  $path = New-RoundRectPath -Rect $r -Radius 12
  $b = New-Object System.Drawing.SolidBrush $Color
  $G.FillPath($b, $path)
  $b.Dispose()
  $path.Dispose()
  $t = New-Object System.Drawing.SolidBrush (Color-Rgb 255 255 255)
  $G.DrawString($Text, $font, $t, $X + 9, $Y + 5)
  $t.Dispose()
  $font.Dispose()
}

function Draw-ModulePcb {
  param(
    [System.Drawing.Graphics]$G,
    [System.Drawing.RectangleF]$Rect,
    [string]$Name,
    [System.Drawing.Color]$PcbColor
  )
  Draw-Shadow -G $G -Rect $Rect -Radius 16 -Layers 10 -OffsetX 9 -OffsetY 11
  $path = New-RoundRectPath -Rect $Rect -Radius 16
  $b = New-Object System.Drawing.SolidBrush $PcbColor
  $G.FillPath($b, $path)
  $b.Dispose()
  $pen = New-Object System.Drawing.Pen (Color-Rgba -A 140 -R 0 -G 0 -B 0), 2.0
  $G.DrawPath($pen, $path)
  $pen.Dispose()
  $path.Dispose()

  # Silkscreen-ish
  $silk = New-Object System.Drawing.SolidBrush (Color-Rgba -A 160 -R 255 -G 255 -B 255)
  $font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
  $G.DrawString($Name, $font, $silk, $Rect.X + 14, $Rect.Y + 12)
  $font.Dispose()
  $silk.Dispose()

  # Black IC blocks
  $ic = New-Object System.Drawing.SolidBrush (Color-Rgb 25 28 33)
  $G.FillRectangle($ic, $Rect.X + 18, $Rect.Y + 46, $Rect.Width * 0.40, $Rect.Height * 0.38)
  $G.FillRectangle($ic, $Rect.X + $Rect.Width * 0.62, $Rect.Y + 56, $Rect.Width * 0.26, $Rect.Height * 0.26)
  $ic.Dispose()
}

function Save-Canvas {
  param($Canvas, [string]$Path)
  $Canvas.g.Dispose()
  $Canvas.bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
  $Canvas.bmp.Dispose()
}

$colSda = Color-Rgb 0 120 212
$colScl = Color-Rgb 0 161 96
$colTx  = Color-Rgb 241 136 0
$colRx  = Color-Rgb 0 120 212
$colGnd = Color-Rgb 30 32 35
$col3v3 = Color-Rgb 232 121 0
$col5v  = Color-Rgb 200 33 41
$colRst = Color-Rgb 132 74 184

$nucleo = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot "nucleo_f401_cc0.jpg"))
$uno = [System.Drawing.Image]::FromFile((Join-Path $PSScriptRoot "arduino_uno_cc0.jpg"))

try {
  # 1) Current hardware wiring
  $c = New-Canvas
  $g = $c.g
  Draw-Header -G $g -Title "Current Hardware Wiring"

  $left = New-Object System.Drawing.RectangleF(50, 130, 840, 890)
  $right = New-Object System.Drawing.RectangleF(910, 130, 840, 890)

  Draw-Card -G $g -Rect $left -Title "STM32 Side (3.3V domain)" `
    -Fill (Color-Rgba 220 220 235 250) -Stroke (Color-Rgb 168 186 206) -TitleFill (Color-Rgb 224 236 250)
  Draw-Card -G $g -Rect $right -Title "Peripherals (5V domain)" `
    -Fill (Color-Rgba 220 243 248 236) -Stroke (Color-Rgb 184 200 170) -TitleFill (Color-Rgb 232 245 226)

  Draw-DomainBadge -G $g -X 70 -Y 196 -Text "3.3V" -Color (Color-Rgb 58 120 214)
  Draw-DomainBadge -G $g -X 930 -Y 196 -Text "5V" -Color (Color-Rgb 220 132 36)

  $nCrop = New-Object System.Drawing.Rectangle -ArgumentList @(18, 18, ($nucleo.Width - 36), ($nucleo.Height - 36))
  $nDest = New-Object System.Drawing.RectangleF(110, 220, 720, 760)
  Crop-AndPlace -G $g -Img $nucleo -Crop $nCrop -Dest $nDest -Radius 22

  # Modules: LCD + DS1307 + divider network
  $lcdRect = New-Object System.Drawing.RectangleF(990, 240, 520, 235)
  Draw-ModulePcb -G $g -Rect $lcdRect -Name "I2C LCD 16x2 (PCF8574)" -PcbColor (Color-Rgb 35 132 80)
  # LCD bezel
  $bezel = New-Object System.Drawing.SolidBrush (Color-Rgb 20 22 25)
  $g.FillRectangle($bezel, $lcdRect.X + 165, $lcdRect.Y + 78, 320, 120)
  $bezel.Dispose()
  $screen = New-Object System.Drawing.SolidBrush (Color-Rgb 26 136 68)
  $g.FillRectangle($screen, $lcdRect.X + 178, $lcdRect.Y + 90, 294, 96)
  $screen.Dispose()

  $rtcRect = New-Object System.Drawing.RectangleF(990, 510, 360, 180)
  Draw-ModulePcb -G $g -Rect $rtcRect -Name "DS1307 RTC" -PcbColor (Color-Rgb 44 94 160)

  $divRect = New-Object System.Drawing.RectangleF(990, 720, 720, 250)
  Draw-Card -G $g -Rect $divRect -Title "Divider Network (Rref + Rx)" `
    -Fill (Color-Rgba 250 250 250 250) -Stroke (Color-Rgb 200 210 220) -TitleFill (Color-Rgb 244 246 249)

  $font = New-Object System.Drawing.Font("Segoe UI", 15, [System.Drawing.FontStyle]::Bold)
  $txt = New-Object System.Drawing.SolidBrush (Color-Rgb 32 38 45)
  $g.DrawString("3.3V  ->  Rref(10k)  ->  NODE  ->  Rx(unknown)  ->  GND", $font, $txt, $divRect.X + 26, $divRect.Y + 90)
  $font.Dispose()
  $txt.Dispose()
  $font2 = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular)
  $txt2 = New-Object System.Drawing.SolidBrush (Color-Rgb 60 72 84)
  $g.DrawString("PA0 reads NODE voltage (ADC1_IN0)", $font2, $txt2, $divRect.X + 26, $divRect.Y + 138)
  $font2.Dispose()
  $txt2.Dispose()

  # Wires (bundle style)
  $pSclA = [System.Drawing.PointF]::new(830, 395)
  $pSclB = [System.Drawing.PointF]::new(990, 325)
  Draw-Wire -G $g -A $pSclA -B $pSclB -Color $colScl -Width 8 -Label "SCL (PB8)" -LabelPos ([System.Drawing.PointF]::new(842, 338))

  $pSdaA = [System.Drawing.PointF]::new(830, 430)
  $pSdaB = [System.Drawing.PointF]::new(990, 355)
  Draw-Wire -G $g -A $pSdaA -B $pSdaB -Color $colSda -Width 8 -Label "SDA (PB9)" -LabelPos ([System.Drawing.PointF]::new(842, 412))

  $p5vA = [System.Drawing.PointF]::new(830, 470)
  $p5vB = [System.Drawing.PointF]::new(990, 390)
  Draw-Wire -G $g -A $p5vA -B $p5vB -Color $col5v -Width 7 -Label "5V (VCC)" -LabelPos ([System.Drawing.PointF]::new(842, 474))

  $pGndA = [System.Drawing.PointF]::new(830, 510)
  $pGndB = [System.Drawing.PointF]::new(990, 420)
  Draw-Wire -G $g -A $pGndA -B $pGndB -Color $colGnd -Width 7 -Label "GND" -LabelPos ([System.Drawing.PointF]::new(860, 528))

  # RTC taps I2C
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(1260, 475)) -B ([System.Drawing.PointF]::new(1200, 510)) -Color $colScl -Width 6 -Label "" -LabelPos ([System.Drawing.PointF]::new(0,0))
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(1320, 475)) -B ([System.Drawing.PointF]::new(1230, 540)) -Color $colSda -Width 6 -Label "" -LabelPos ([System.Drawing.PointF]::new(0,0))

  # Divider node -> PA0
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(830, 650)) -B ([System.Drawing.PointF]::new(1020, 805)) -Color (Color-Rgb 168 74 196) -Width 7 -Label "ADC NODE (PA0)" -LabelPos ([System.Drawing.PointF]::new(860, 668))

  Save-Canvas -Canvas $c -Path (Join-Path $OutDir "current_hw_wiring.png")

  # 2) Programmer wiring
  $c = New-Canvas
  $g = $c.g
  Draw-Header -G $g -Title "External ST-Link SWD Wiring"

  $prog = New-Object System.Drawing.RectangleF(50, 130, 840, 890)
  $tgt  = New-Object System.Drawing.RectangleF(910, 130, 840, 890)
  Draw-Card -G $g -Rect $prog -Title "Programmer" `
    -Fill (Color-Rgba 220 222 236 248) -Stroke (Color-Rgb 168 186 206) -TitleFill (Color-Rgb 224 236 250)
  Draw-Card -G $g -Rect $tgt -Title "Target (3.3V)" `
    -Fill (Color-Rgba 220 236 248 236) -Stroke (Color-Rgb 184 200 170) -TitleFill (Color-Rgb 232 245 226)

  # Draw a "ST-Link dongle" as a pseudo-photo module
  $stRect = New-Object System.Drawing.RectangleF(120, 240, 680, 330)
  Draw-ModulePcb -G $g -Rect $stRect -Name "ST-Link V2/V3" -PcbColor (Color-Rgb 50 54 60)
  $lab = New-Object System.Drawing.SolidBrush (Color-Rgba 210 255 255 255)
  $fnt = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
  $g.DrawString("SWD", $fnt, $lab, $stRect.X + 26, $stRect.Y + 88)
  $fnt.Dispose(); $lab.Dispose()

  # Target uses the real Nucleo photo (bigger)
  $nDest2 = New-Object System.Drawing.RectangleF(980, 220, 720, 760)
  Crop-AndPlace -G $g -Img $nucleo -Crop $nCrop -Dest $nDest2 -Radius 22

  # Wire bundles
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(780, 315)) -B ([System.Drawing.PointF]::new(980, 355)) -Color $colTx -Width 8 -Label "SWDIO" -LabelPos ([System.Drawing.PointF]::new(820, 285))
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(780, 365)) -B ([System.Drawing.PointF]::new(980, 405)) -Color $colRx -Width 8 -Label "SWCLK" -LabelPos ([System.Drawing.PointF]::new(820, 335))
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(780, 425)) -B ([System.Drawing.PointF]::new(980, 465)) -Color $colGnd -Width 7 -Label "GND" -LabelPos ([System.Drawing.PointF]::new(840, 437))
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(780, 485)) -B ([System.Drawing.PointF]::new(980, 525)) -Color $col3v3 -Width 7 -Label "3V3 (ref)" -LabelPos ([System.Drawing.PointF]::new(820, 495))
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(780, 545)) -B ([System.Drawing.PointF]::new(980, 585)) -Color $colRst -Width 7 -Label "NRST (opt)" -LabelPos ([System.Drawing.PointF]::new(810, 565))

  $warnRect = New-Object System.Drawing.RectangleF(140, 770, 1520, 200)
  Draw-Card -G $g -Rect $warnRect -Title "Safety Notes" `
    -Fill (Color-Rgba 250 250 245 245) -Stroke (Color-Rgb 210 210 210) -TitleFill (Color-Rgb 246 246 246)
  $wf = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
  $wb = New-Object System.Drawing.SolidBrush (Color-Rgb 150 40 40)
  $g.DrawString("Do NOT inject 5V into target 3.3V IO. Keep common GND and short SWD wires.", $wf, $wb, $warnRect.X + 26, $warnRect.Y + 86)
  $wf.Dispose(); $wb.Dispose()

  Save-Canvas -Canvas $c -Path (Join-Path $OutDir "programmer_wiring_stlink.png")

  # 3) Phase 1 UART wiring
  $c = New-Canvas
  $g = $c.g
  Draw-Header -G $g -Title "Phase 1 - UART Protocol Wiring"

  $stm = New-Object System.Drawing.RectangleF(50, 130, 560, 890)
  $mid = New-Object System.Drawing.RectangleF(640, 200, 520, 820)
  $unoCard = New-Object System.Drawing.RectangleF(1190, 130, 560, 890)

  Draw-Card -G $g -Rect $stm -Title "STM32 Host (3.3V)" `
    -Fill (Color-Rgba 220 220 235 250) -Stroke (Color-Rgb 168 186 206) -TitleFill (Color-Rgb 224 236 250)
  Draw-Card -G $g -Rect $mid -Title "Level Shifter" `
    -Fill (Color-Rgba 250 246 234 250) -Stroke (Color-Rgb 210 196 156) -TitleFill (Color-Rgb 248 240 220)
  Draw-Card -G $g -Rect $unoCard -Title "Arduino Uno (5V)" `
    -Fill (Color-Rgba 220 236 248 236) -Stroke (Color-Rgb 184 200 170) -TitleFill (Color-Rgb 232 245 226)

  Crop-AndPlace -G $g -Img $nucleo -Crop $nCrop -Dest (New-Object System.Drawing.RectangleF(90, 230, 500, 720)) -Radius 22

  $uCrop = New-Object System.Drawing.Rectangle -ArgumentList @(40, 40, ($uno.Width - 80), ($uno.Height - 90))
  Crop-AndPlace -G $g -Img $uno -Crop $uCrop -Dest (New-Object System.Drawing.RectangleF(1230, 250, 500, 700)) -Radius 22

  Draw-ModulePcb -G $g -Rect (New-Object System.Drawing.RectangleF(690, 310, 420, 340)) -Name "Bi-dir level shifter" -PcbColor (Color-Rgb 32 36 44)
  Draw-DomainBadge -G $g -X 705 -Y 610 -Text "LV=3.3V" -Color (Color-Rgb 58 120 214)
  Draw-DomainBadge -G $g -X 875 -Y 610 -Text "HV=5V" -Color (Color-Rgb 220 132 36)

  # UART wires
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(590, 390)) -B ([System.Drawing.PointF]::new(690, 390)) -Color $colTx -Width 8 -Label "TX (PA2)" -LabelPos ([System.Drawing.PointF]::new(470, 360))
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(590, 455)) -B ([System.Drawing.PointF]::new(690, 455)) -Color $colRx -Width 8 -Label "RX (PA3)" -LabelPos ([System.Drawing.PointF]::new(470, 425))
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(590, 520)) -B ([System.Drawing.PointF]::new(690, 520)) -Color $colGnd -Width 7 -Label "GND" -LabelPos ([System.Drawing.PointF]::new(505, 535))

  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(1110, 390)) -B ([System.Drawing.PointF]::new(1230, 420)) -Color $colTx -Width 8 -Label "RX (D0)" -LabelPos ([System.Drawing.PointF]::new(1120, 348))
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(1110, 455)) -B ([System.Drawing.PointF]::new(1230, 470)) -Color $colRx -Width 8 -Label "TX (D1)" -LabelPos ([System.Drawing.PointF]::new(1120, 487))
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(1110, 520)) -B ([System.Drawing.PointF]::new(1230, 520)) -Color $colGnd -Width 7 -Label "" -LabelPos ([System.Drawing.PointF]::new(0,0))

  $frameRect = New-Object System.Drawing.RectangleF(640, 740, 1110, 240)
  Draw-Card -G $g -Rect $frameRect -Title "Protocol Frame" `
    -Fill (Color-Rgba 250 250 250 250) -Stroke (Color-Rgb 200 210 220) -TitleFill (Color-Rgb 244 246 249)
  $ff = New-Object System.Drawing.Font("Consolas", 16, [System.Drawing.FontStyle]::Bold)
  $fb = New-Object System.Drawing.SolidBrush (Color-Rgb 28 33 39)
  $g.DrawString("SOF | VER | TYPE | SEQ | LEN | PAYLOAD | CRC16", $ff, $fb, $frameRect.X + 26, $frameRect.Y + 88)
  $ff.Dispose(); $fb.Dispose()
  $sf = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Regular)
  $sb = New-Object System.Drawing.SolidBrush (Color-Rgb 70 82 94)
  $g.DrawString("ACK/NACK + Retry (max=3) + Timeout", $sf, $sb, $frameRect.X + 26, $frameRect.Y + 134)
  $sf.Dispose(); $sb.Dispose()

  Save-Canvas -Canvas $c -Path (Join-Path $OutDir "phase1_uart_protocol_wiring.png")

  # 4) Phase 2 dual node integration
  $c = New-Canvas
  $g = $c.g
  Draw-Header -G $g -Title "Phase 2 - Dual Node Integration"

  $left2 = New-Object System.Drawing.RectangleF(50, 130, 840, 890)
  $right2 = New-Object System.Drawing.RectangleF(910, 130, 840, 890)

  Draw-Card -G $g -Rect $left2 -Title "STM32 Main Controller" `
    -Fill (Color-Rgba 220 220 235 250) -Stroke (Color-Rgb 168 186 206) -TitleFill (Color-Rgb 224 236 250)
  Draw-Card -G $g -Rect $right2 -Title "Uno Sensor Node" `
    -Fill (Color-Rgba 220 236 248 236) -Stroke (Color-Rgb 184 200 170) -TitleFill (Color-Rgb 232 245 226)

  Crop-AndPlace -G $g -Img $nucleo -Crop $nCrop -Dest (New-Object System.Drawing.RectangleF(110, 220, 720, 640)) -Radius 22
  Crop-AndPlace -G $g -Img $uno -Crop $uCrop -Dest (New-Object System.Drawing.RectangleF(980, 220, 720, 540)) -Radius 22

  $busRect = New-Object System.Drawing.RectangleF(120, 880, 760, 120)
  Draw-Card -G $g -Rect $busRect -Title "LCD + DS1307 (I2C bus)" `
    -Fill (Color-Rgba 250 250 250 250) -Stroke (Color-Rgb 200 210 220) -TitleFill (Color-Rgb 244 246 249)
  Draw-Sticker -G $g -X 160 -Y 942 -Text "PB8=SCL, PB9=SDA" -Accent $colScl
  Draw-Sticker -G $g -X 420 -Y 942 -Text "200ms refresh" -Accent (Color-Rgb 90 110 130)

  $potRect = New-Object System.Drawing.RectangleF(980, 780, 560, 220)
  Draw-Card -G $g -Rect $potRect -Title "Potentiometer (A0)" `
    -Fill (Color-Rgba 250 250 250 250) -Stroke (Color-Rgb 200 210 220) -TitleFill (Color-Rgb 244 246 249)
  # Simple pot drawing
  $potBody = New-Object System.Drawing.SolidBrush (Color-Rgb 60 66 74)
  $g.FillRectangle($potBody, $potRect.X + 46, $potRect.Y + 92, 220, 80)
  $potBody.Dispose()
  $potKnob = New-Object System.Drawing.SolidBrush (Color-Rgb 210 210 210)
  $g.FillEllipse($potKnob, $potRect.X + 220, $potRect.Y + 70, 120, 120)
  $potKnob.Dispose()

  # Integration links
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(830, 540)) -B ([System.Drawing.PointF]::new(980, 520)) -Color $colTx -Width 8 -Label "UART (poll)" -LabelPos ([System.Drawing.PointF]::new(820, 500))
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(830, 600)) -B ([System.Drawing.PointF]::new(980, 580)) -Color $colGnd -Width 7 -Label "GND" -LabelPos ([System.Drawing.PointF]::new(860, 620))
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new(1500, 760)) -B ([System.Drawing.PointF]::new(1320, 835)) -Color $colScl -Width 7 -Label "A0" -LabelPos ([System.Drawing.PointF]::new(1440, 804))

  $goalRect = New-Object System.Drawing.RectangleF(1560, 780, 180, 220)
  Draw-Card -G $g -Rect $goalRect -Title "Goal" `
    -Fill (Color-Rgba 255 255 255 255) -Stroke (Color-Rgb 220 220 220) -TitleFill (Color-Rgb 246 246 246)
  $gf = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
  $gb = New-Object System.Drawing.SolidBrush (Color-Rgb 45 55 65)
  $g.DrawString("Local Rx +", $gf, $gb, $goalRect.X + 16, $goalRect.Y + 90)
  $g.DrawString("Remote node", $gf, $gb, $goalRect.X + 16, $goalRect.Y + 114)
  $g.DrawString("Degraded ok", $gf, $gb, $goalRect.X + 16, $goalRect.Y + 154)
  $gf.Dispose(); $gb.Dispose()

  Save-Canvas -Canvas $c -Path (Join-Path $OutDir "phase2_dual_node_wiring.png")

  # 5) Phase 3 state machine + scheduler (keep more "hardware" vibe via photos)
  $c = New-Canvas
  $g = $c.g
  Draw-Header -G $g -Title "Phase 3 - State Machine + Non-blocking Scheduler"

  $sched = New-Object System.Drawing.RectangleF(50, 130, 840, 890)
  $states = New-Object System.Drawing.RectangleF(910, 130, 840, 890)
  Draw-Card -G $g -Rect $sched -Title "Task Scheduler (5ms tick)" `
    -Fill (Color-Rgba 220 220 235 250) -Stroke (Color-Rgb 168 186 206) -TitleFill (Color-Rgb 224 236 250)
  Draw-Card -G $g -Rect $states -Title "System States" `
    -Fill (Color-Rgba 220 236 248 236) -Stroke (Color-Rgb 184 200 170) -TitleFill (Color-Rgb 232 245 226)

  # Mini "system photo strip" on top of each card
  Crop-AndPlace -G $g -Img $nucleo -Crop $nCrop -Dest (New-Object System.Drawing.RectangleF(90, 210, 360, 220)) -Radius 18
  Crop-AndPlace -G $g -Img $uno -Crop $uCrop -Dest (New-Object System.Drawing.RectangleF(470, 210, 360, 220)) -Radius 18
  Draw-Sticker -G $g -X 92 -Y 440 -Text "I2C + ADC + LCD" -Accent $colSda
  Draw-Sticker -G $g -X 472 -Y 440 -Text "UART node link" -Accent $colTx

  # Scheduler task tiles
  $tiles = @(
    @{ n="adc_task"; t="20ms"; x=130; y=520 },
    @{ n="node_poll"; t="200ms"; x=410; y=520 },
    @{ n="lcd_task"; t="200ms"; x=690; y=520 },
    @{ n="stream"; t="rate"; x=270; y=710 },
    @{ n="diag"; t="1000ms"; x=560; y=710 }
  )
  foreach ($tile in $tiles) {
    $r = New-Object System.Drawing.RectangleF($tile.x, $tile.y, 230, 140)
    Draw-Card -G $g -Rect $r -Title "" -Fill (Color-Rgba 255 255 255 255) -Stroke (Color-Rgb 205 215 228) -TitleFill (Color-Rgb 255 255 255)
    $tf = New-Object System.Drawing.Font("Consolas", 12, [System.Drawing.FontStyle]::Bold)
    $tb = New-Object System.Drawing.SolidBrush (Color-Rgb 28 33 39)
    $g.DrawString($tile.n, $tf, $tb, $r.X + 18, $r.Y + 44)
    $g.DrawString($tile.t, $tf, $tb, $r.X + 18, $r.Y + 70)
    $tf.Dispose(); $tb.Dispose()
  }

  # State machine bubbles
  function Draw-State {
    param([string]$Name, [float]$X, [float]$Y, [System.Drawing.Color]$Fill)
    $r = New-Object System.Drawing.RectangleF($X, $Y, 230, 120)
    Draw-Shadow -G $g -Rect $r -Radius 22 -Layers 10 -OffsetX 10 -OffsetY 12
    $p = New-RoundRectPath -Rect $r -Radius 22
    $b = New-Object System.Drawing.SolidBrush $Fill
    $g.FillPath($b, $p)
    $b.Dispose()
    $pen = New-Object System.Drawing.Pen (Color-Rgba -A 140 -R 0 -G 0 -B 0), 2.0
    $g.DrawPath($pen, $p)
    $pen.Dispose()
    $p.Dispose()
    $f = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $br = New-Object System.Drawing.SolidBrush (Color-Rgb 25 30 36)
    $g.DrawString($Name, $f, $br, $X + 64, $Y + 42)
    $f.Dispose(); $br.Dispose()
    return $r
  }

  $init = Draw-State -Name "INIT" -X 980 -Y 290 -Fill (Color-Rgb 232 246 236)
  $wait = Draw-State -Name "LINK_WAIT" -X 1240 -Y 290 -Fill (Color-Rgb 232 246 236)
  $run  = Draw-State -Name "RUN" -X 1500 -Y 290 -Fill (Color-Rgb 232 246 236)
  $deg  = Draw-State -Name "DEGRADED" -X 1100 -Y 500 -Fill (Color-Rgb 250 244 232)
  $flt  = Draw-State -Name "FAULT" -X 1450 -Y 520 -Fill (Color-Rgb 252 235 236)

  # Transitions
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new($init.X + 230, $init.Y + 60)) -B ([System.Drawing.PointF]::new($wait.X, $wait.Y + 60)) -Color (Color-Rgb 0 140 92) -Width 7 -Label "" -LabelPos ([System.Drawing.PointF]::new(0,0))
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new($wait.X + 230, $wait.Y + 60)) -B ([System.Drawing.PointF]::new($run.X, $run.Y + 60)) -Color (Color-Rgb 0 140 92) -Width 7 -Label "" -LabelPos ([System.Drawing.PointF]::new(0,0))
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new($run.X + 60, $run.Y + 120)) -B ([System.Drawing.PointF]::new($deg.X + 120, $deg.Y)) -Color (Color-Rgb 241 136 0) -Width 7 -Label "recover" -LabelPos ([System.Drawing.PointF]::new(1325, 430))
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new($deg.X + 200, $deg.Y + 10)) -B ([System.Drawing.PointF]::new($run.X + 30, $run.Y + 110)) -Color (Color-Rgb 0 140 92) -Width 7 -Label "" -LabelPos ([System.Drawing.PointF]::new(0,0))
  Draw-Wire -G $g -A ([System.Drawing.PointF]::new($run.X + 180, $run.Y + 120)) -B ([System.Drawing.PointF]::new($flt.X + 40, $flt.Y)) -Color (Color-Rgb 180 40 45) -Width 7 -Label "critical" -LabelPos ([System.Drawing.PointF]::new(1600, 470))

  $polRect = New-Object System.Drawing.RectangleF(980, 760, 720, 220)
  Draw-Card -G $g -Rect $polRect -Title "Policy" `
    -Fill (Color-Rgba 255 255 255 255) -Stroke (Color-Rgb 200 210 220) -TitleFill (Color-Rgb 244 246 249)
  $pf = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
  $pb = New-Object System.Drawing.SolidBrush (Color-Rgb 45 55 65)
  $g.DrawString("timeout / retry / crc counter / fault inject", $pf, $pb, $polRect.X + 22, $polRect.Y + 88)
  $pf.Dispose(); $pb.Dispose()
  $pf2 = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Regular)
  $pb2 = New-Object System.Drawing.SolidBrush (Color-Rgb 70 82 94)
  $g.DrawString("No blocking delays on main path", $pf2, $pb2, $polRect.X + 22, $polRect.Y + 128)
  $pf2.Dispose(); $pb2.Dispose()

  Save-Canvas -Canvas $c -Path (Join-Path $OutDir "phase3_state_machine.png")
}
finally {
  $nucleo.Dispose()
  $uno.Dispose()
}

Write-Output "Rendered diagrams to $OutDir"
