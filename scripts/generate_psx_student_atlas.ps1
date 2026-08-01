# Generate 128x128 PSX student texture atlas (flat colors, packed UV layout)
Add-Type -AssemblyName System.Drawing

$W = 128
$H = 128

function New-Color([int]$r,[int]$g,[int]$b) { return [System.Drawing.Color]::FromArgb(255,$r,$g,$b) }

$BG = New-Color 26 16 40
$SHIRT = New-Color 212 168 42
$SHIRT_SIDE = New-Color 184 137 31
$SHIRT_BACK = New-Color 170 128 28
$JEANS = New-Color 91 127 168
$JEANS_SIDE = New-Color 74 106 143
$JEANS_BACK = New-Color 64 92 128
$SKIN = New-Color 198 134 66
$SKIN_SIDE = New-Color 170 115 56
$HAIR = New-Color 31 24 20
$HAIR_SIDE = New-Color 24 18 15
$SHOE = New-Color 138 138 138
$SHOE_SIDE = New-Color 118 118 118
$SHOE_SOLE = New-Color 92 92 92
$INK = New-Color 26 22 20
$BUTTON = New-Color 120 90 35
$POCKET = New-Color 196 154 38
$LIP = New-Color 139 77 77
$WHITE = New-Color 230 220 200

$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear($BG)

function Fill-Rect($bmp, $uv, $color) {
  $u1,$v1,$u2,$v2 = $uv
  $x0 = [Math]::Min([int][Math]::Round($u1), [int][Math]::Round($u2))
  $x1 = [Math]::Max([int][Math]::Round($u1), [int][Math]::Round($u2))
  $y0 = [Math]::Min([int][Math]::Round($v1), [int][Math]::Round($v2))
  $y1 = [Math]::Max([int][Math]::Round($v1), [int][Math]::Round($v2))
  for ($y = $y0; $y -lt $y1; $y++) {
    for ($x = $x0; $x -lt $x1; $x++) {
      if ($x -ge 0 -and $x -lt $W -and $y -ge 0 -and $y -lt $H) { $bmp.SetPixel($x,$y,$color) }
    }
  }
  return @($x0,$y0,$x1,$y1)
}

function Set-Px($bmp,$x,$y,$color) {
  if ($x -ge 0 -and $x -lt $W -and $y -ge 0 -and $y -lt $H) { $bmp.SetPixel($x,$y,$color) }
}

$UV = @{
  torso = @{ north=@(4,4,11,10); east=@(0,4,4,10); south=@(15,4,22,10); west=@(11,4,15,10); up=@(11,4,4,0); down=@(18,0,11,4) }
  head = @{ north=@(53,4,57,8); east=@(49,4,53,8); south=@(61,4,65,8); west=@(57,4,61,8); up=@(57,4,53,0); down=@(61,0,57,4) }
  hair = @{ north=@(72,4,76,5); east=@(68,4,72,5); south=@(80,4,84,5); west=@(76,4,80,5); up=@(76,4,72,0); down=@(80,0,76,4) }
  arm_l = @{ north=@(91,2,92,7); east=@(89,2,91,7); south=@(94,2,95,7); west=@(92,2,94,7); up=@(92,2,91,0); down=@(93,0,92,2) }
  arm_r = @{ north=@(100,2,101,7); east=@(98,2,100,7); south=@(103,2,104,7); west=@(101,2,103,7); up=@(101,2,100,0); down=@(102,0,101,2) }
  leg_l = @{ north=@(26,3,28,10); east=@(23,3,26,10); south=@(31,3,33,10); west=@(28,3,31,10); up=@(28,3,26,0); down=@(30,0,28,3) }
  leg_r = @{ north=@(39,3,41,10); east=@(36,3,39,10); south=@(44,3,46,10); west=@(41,3,44,10); up=@(41,3,39,0); down=@(43,0,41,3) }
  shoe_l = @{ north=@(110,3,112,5); east=@(107,3,110,5); south=@(115,3,117,5); west=@(112,3,115,5); up=@(112,3,110,0); down=@(114,0,112,3) }
  shoe_r = @{ north=@(3,15,5,17); east=@(0,15,3,17); south=@(8,15,10,17); west=@(5,15,8,17); up=@(5,15,3,12); down=@(7,12,5,15) }
}

function Paint-Sides($part, $map) {
  foreach ($face in $map.Keys) {
    if ($face -eq 'north') { continue }
    Fill-Rect $bmp $UV[$part][$face] $map[$face] | Out-Null
  }
}

# Torso
Paint-Sides torso @{ east=$SHIRT_SIDE; west=$SHIRT_SIDE; south=$SHIRT_BACK; up=$SHIRT; down=$SHIRT_SIDE }
$b = Fill-Rect $bmp $UV.torso.north $SHIRT
$cx = [int](($b[0]+$b[2])/2)
for ($x=$cx-1; $x -le $cx+1; $x++) { Set-Px $bmp $x $b[1] $SKIN; Set-Px $bmp $x ($b[1]+1) $SKIN }
for ($y=$b[1]+2; $y -lt $b[3]-1; $y++) { Set-Px $bmp $cx $y $BUTTON }
for ($y=$b[1]+2; $y -lt $b[1]+4; $y++) { for ($x=$b[0]+1; $x -lt $b[0]+3; $x++) { Set-Px $bmp $x $y $POCKET } }
Set-Px $bmp ($b[0]+2) ($b[1]+2) $INK

# Head
Paint-Sides head @{ east=$SKIN_SIDE; west=$SKIN_SIDE; south=$SKIN_SIDE; up=$HAIR; down=$SKIN }
$b = Fill-Rect $bmp $UV.head.north $SKIN
for ($x=$b[0]; $x -lt $b[2]; $x++) { Set-Px $bmp $x $b[1] $HAIR; Set-Px $bmp $x ($b[1]+1) $HAIR }
Set-Px $bmp ($b[0]+1) ($b[1]+2) $INK
Set-Px $bmp ($b[2]-2) ($b[1]+2) $INK
Set-Px $bmp ($b[0]+1) ($b[1]+1) $HAIR
Set-Px $bmp ($b[2]-2) ($b[1]+1) $HAIR
Set-Px $bmp ($b[0]+2) ($b[3]-2) $LIP

# Hair
foreach ($f in @('east','west','south','up','down')) { Fill-Rect $bmp $UV.hair[$f] $(if($f -eq 'down'){$SKIN}else{$HAIR}) | Out-Null }
$b = Fill-Rect $bmp $UV.hair.north $HAIR
for ($x=$b[0]; $x -lt $b[2]; $x++) { if ((($x-$b[0])%2) -eq 0) { Set-Px $bmp $x $b[1] $HAIR_SIDE } }

# Arms
foreach ($arm in @('arm_l','arm_r')) {
  Paint-Sides $arm @{ east=$SHIRT_SIDE; west=$SHIRT_SIDE; south=$SHIRT_SIDE; up=$SHIRT; down=$SHIRT_SIDE }
  $b = Fill-Rect $bmp $UV[$arm].north $SHIRT
  $cx = [int](($b[0]+$b[2])/2)
  for ($y=$b[1]; $y -lt $b[3]; $y++) { Set-Px $bmp $cx $y $SHIRT_SIDE }
}

# Legs
foreach ($leg in @('leg_l','leg_r')) {
  Paint-Sides $leg @{ east=$JEANS_SIDE; west=$JEANS_SIDE; south=$JEANS_BACK; up=$JEANS; down=$JEANS_SIDE }
  $b = Fill-Rect $bmp $UV[$leg].north $JEANS
  $cx = [int](($b[0]+$b[2])/2)
  for ($y=$b[1]; $y -lt $b[3]; $y++) { Set-Px $bmp $cx $y $JEANS_SIDE }
  for ($x=$b[0]; $x -lt $b[2]; $x++) { Set-Px $bmp $x ($b[3]-1) $JEANS_BACK }
}

# Shoes
foreach ($sh in @('shoe_l','shoe_r')) {
  Paint-Sides $sh @{ east=$SHOE_SIDE; west=$SHOE_SIDE; south=$SHOE_SIDE; up=$SHOE; down=$SHOE_SOLE }
  $b = Fill-Rect $bmp $UV[$sh].north $SHOE
  for ($x=$b[0]; $x -lt $b[2]; $x++) { Set-Px $bmp $x ($b[3]-1) $SHOE_SOLE }
  for ($x=$b[0]+1; $x -lt $b[2]-1; $x++) { Set-Px $bmp $x $b[1] $WHITE }
}

$out = "C:\Users\Ariel\Documents\New project\assets\npcs\psx_student_civilian_atlas.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()
Write-Output $out
