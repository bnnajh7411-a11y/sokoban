$root = 'D:\Workspace05\sokoban'

function Replace-OnceRegex {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Replacement
    )

    return [regex]::new(
        $Pattern,
        [System.Text.RegularExpressions.RegexOptions]::Singleline -bor [System.Text.RegularExpressions.RegexOptions]::Multiline
    ).Replace($Text, $Replacement, 1)
}

function Save-Text {
    param(
        [string]$Path,
        [string]$Text
    )

    Set-Content -Path $Path -Value $Text -Encoding utf8
}

$stage1Path = Join-Path $root 'scenes\Stage1.tscn'
$stage1 = Get-Content -Raw -Path $stage1Path
$stage1 = Replace-OnceRegex $stage1 '(?m)^\[node name=\\\r?\n\r?\n' @'
[ext_resource type="PackedScene" path="res://scenes/GameUI.tscn" id="4_ui"]
[ext_resource type="Script" uid="uid://cblu8a023gdar" path="res://gds/Stage1Tutorial.gd" id="5_tutorial"]

[node name="Stage" type="Node2D" unique_id=1683069215]
'@
$stage1 = $stage1.Replace(
    'language = "ko_KR"[node name="Sheep" parent="." unique_id=1311717518 instance=ExtResource("2_hp1su")]',
    'language = "ko_KR"`r`n`r`n[node name="Sheep" parent="." unique_id=1311717518 instance=ExtResource("2_hp1su")]'
)
Save-Text $stage1Path $stage1

$sharedStages = @(
    @{
        Path = 'scenes\Stage2.tscn'
        StageUid = '1683069215'
        RootLine = '[node name="Stage" type="Node2D" unique_id=1683069215]'
        SheepUnique = '1311717518'
        SheepId = '2_4bw56'
    },
    @{
        Path = 'scenes\Stage3.tscn'
        StageUid = '1683069215'
        RootLine = '[node name="Stage" type="Node2D" unique_id=1683069215]'
        SheepUnique = '1311717518'
        SheepId = '3_asesr'
    },
    @{
        Path = 'scenes\Stage5.tscn'
        StageUid = '1683069215'
        RootLine = '[node name="Stage" type="Node2D" unique_id=1683069215]'
        SheepUnique = '1311717518'
        SheepId = '5_864yv'
    },
    @{
        Path = 'scenes\Stage6.tscn'
        StageUid = '1683069215'
        RootLine = '[node name="Stage" type="Node2D" unique_id=1683069215]'
        SheepUnique = '1311717518'
        SheepId = '5_wx3gq'
    }
)

foreach ($stage in $sharedStages) {
    $path = Join-Path $root $stage.Path
    $text = Get-Content -Raw -Path $path
    $text = $text.Replace(
        '[ext_resource type="PackedScene" path="res://scenes/GameUI.tscn" id="5_ui"]`r`n`r`n[node name="Stage" type="Node2D" unique_id=1683069215]',
        "[ext_resource type=`"PackedScene`" path=`"res://scenes/GameUI.tscn`" id=`"5_ui`"]`r`n`r`n$($stage.RootLine)"
    )
    $text = $text.Replace(
        "[node name=`"CanvasLayer`" parent=`"`.`" instance=ExtResource(`"5_ui`")][node name=`"Sheep`" parent=`"`.`" unique_id=$($stage.SheepUnique) instance=ExtResource(`"$($stage.SheepId)`")]",
        "[node name=`"CanvasLayer`" parent=`"`.`" instance=ExtResource(`"5_ui`")]`r`n`r`n[node name=`"Sheep`" parent=`"`.`" unique_id=$($stage.SheepUnique) instance=ExtResource(`"$($stage.SheepId)`")]"
    )
    Save-Text $path $text
}

$stage4Path = Join-Path $root 'scenes\Stage4.tscn'
$stage4 = Get-Content -Raw -Path $stage4Path
$stage4 = $stage4.Replace(
    '[ext_resource type="PackedScene" path="res://scenes/GameUI.tscn" id="5_ui"]`r`n`r`n[node name="Stage" type="Node2D" unique_id=598128310]',
    '[ext_resource type="PackedScene" path="res://scenes/GameUI.tscn" id="5_ui"]' + "`r`n`r`n" + '[node name="Stage" type="Node2D" unique_id=598128310]'
)
$stage4 = Replace-OnceRegex $stage4 '(?s)\r?\n\[node name="CanvasLayer" type="CanvasLayer" parent="\." unique_id=1468176642\].*?\r?\n(?=\[node name="Sheep" parent="\." )' @'

[node name="CanvasLayer" parent="." instance=ExtResource("5_ui")]
'@
Save-Text $stage4Path $stage4
