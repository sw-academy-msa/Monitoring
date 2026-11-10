# 고정 버전의 공식 배포 파일을 내려받고 저장소가 제공하는 SHA-256과 비교한 뒤 설치합니다.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$version = '1.5.0'
$uri = 'https://github.com/prometheus/jmx_exporter/releases/download/' + $version + '/jmx_prometheus_javaagent-' + $version + '.jar'
$target = Join-Path $root 'vendor\jmx_prometheus_javaagent.jar'
$temp = $target + '.download'
[IO.Directory]::CreateDirectory((Split-Path $target -Parent)) | Out-Null
$checksum = '0315f3f657876302c6205a98d4036ec775dca529c5d0419ca60ee669c688239f'
if ($checksum -notmatch '^[a-fA-F0-9]{64}$') { throw 'Invalid upstream SHA-256; existing jar preserved.' }
Invoke-WebRequest -UseBasicParsing -Uri $uri -OutFile $temp
if ((Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash -ine $checksum) { throw 'JMX checksum mismatch; existing jar preserved.' }
[IO.File]::WriteAllBytes($target,[IO.File]::ReadAllBytes($temp))
Write-Host 'Pinned JMX agent downloaded and SHA-256 verified. Kafka was not restarted.'
