$root = 'D:\Workspace05\sokoban'
$path = Join-Path $root 'scenes\Stage4.tscn'

$text = Get-Content -Raw -Path $path
$text = $text.Replace(
    '[node name="Stage" type="Node2D" unique_id=598128310]',
    '[ext_resource type="PackedScene" path="res://scenes/GameUI.tscn" id="5_ui"]' + "`r`n`r`n" + '[node name="Stage" type="Node2D" unique_id=598128310]'
)
$canvasStart = $text.IndexOf('[node name="CanvasLayer" type="CanvasLayer" parent="." unique_id=1468176642]')
$playerStart = $text.IndexOf('[node name="Player" parent="." unique_id=1088558520 instance=ExtResource("3_be11i")]')

if ($canvasStart -lt 0) {
    throw 'Unable to locate the Stage4 UI block.'
}

$text = $text.Substring(0, $canvasStart) + "[node name=""CanvasLayer"" parent=""."" instance=ExtResource(""5_ui"")]`r`n"

Set-Content -Path $path -Value $text -Encoding utf8
