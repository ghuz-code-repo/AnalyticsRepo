# Golden House - Start All Services
# Zapusk Docker Compose servisov v pravilnom poryadke
#
# Start order:
#   1. Git pull all repositories
#   2. !gateway (nginx + auth-service + mongo)
#   3. Wait for gateway healthcheck
#   4. !gateway/monitoring-service
#   5. !gateway/notification-service
#   6. client_service
#   7. apartment_finder
#   8. referal
#   9. Final status

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$baseDir = $PSScriptRoot
$gatewayDir = Join-Path -Path $baseDir -ChildPath "!gateway"
$startTime = Get-Date
$failedServices = [System.Collections.ArrayList]::new()
$succeededServices = [System.Collections.ArrayList]::new()

# ----------------------------------------
# Functions
# ----------------------------------------

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host ">> $Message" -ForegroundColor Cyan
}

function Write-Ok {
    param([string]$Message)
    Write-Host "   [OK] $Message" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Message)
    Write-Host "   [FAIL] $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "   $Message" -ForegroundColor Yellow
}

function Update-Repository {
    param(
        [string]$RepoPath,
        [string]$RepoName
    )

    $gitDir = Join-Path -Path $RepoPath -ChildPath ".git"
    if (-not (Test-Path $gitDir)) {
        Write-Info "$RepoName - not a git repo, skipping"
        return
    }

    Write-Info "Git pull $RepoName..."
    Push-Location $RepoPath
    try {
        git fetch --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "git fetch $RepoName"
            return
        }
        git pull --quiet 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "git pull $RepoName"
            return
        }
        Write-Ok "$RepoName updated"
    }
    finally {
        Pop-Location
    }
}

function Start-DockerService {
    param(
        [string]$ServicePath,
        [string]$ServiceName
    )

    $ymlPath = Join-Path $ServicePath "docker-compose.yml"
    $yamlPath = Join-Path $ServicePath "docker-compose.yaml"
    $hasCompose = (Test-Path $ymlPath) -or (Test-Path $yamlPath)

    if (-not $hasCompose) {
        Write-Fail "$ServiceName - docker-compose not found in $ServicePath"
        $null = $script:failedServices.Add($ServiceName)
        return $false
    }

    Write-Info "docker compose up --build -d [$ServiceName]..."
    Push-Location $ServicePath
    try {
        docker compose up --build -d 2>&1 | ForEach-Object {
            Write-Host "   $_" -ForegroundColor DarkGray
        }
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "$ServiceName started"
            $null = $script:succeededServices.Add($ServiceName)
            return $true
        }
        else {
            Write-Fail "$ServiceName - docker compose failed"
            $null = $script:failedServices.Add($ServiceName)
            return $false
        }
    }
    finally {
        Pop-Location
    }
}

function Wait-ForHealthy {
    param(
        [string]$ContainerName,
        [int]$TimeoutSeconds = 60
    )

    Write-Info "Waiting for healthcheck $ContainerName (timeout ${TimeoutSeconds}s)..."
    $elapsed = 0
    $fmt = '{{.State.Health.Status}}'
    $health = "unknown"
    while ($elapsed -lt $TimeoutSeconds) {
        try {
            $health = (docker inspect --format $fmt $ContainerName 2>$null)
        }
        catch {
            $health = "not_found"
        }
        if ($health -eq "healthy") {
            Write-Ok "$ContainerName - healthy"
            return $true
        }
        Start-Sleep -Seconds 2
        $elapsed += 2
    }
    Write-Fail "$ContainerName - not healthy after ${TimeoutSeconds}s (current: $health)"
    return $false
}

# ----------------------------------------
# Main
# ----------------------------------------

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  GOLDEN HOUSE - Start All Services"         -ForegroundColor Cyan
$dateStr = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "  $dateStr"                                   -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan

# -- Step 1: Git pull --
Write-Step "Step 1/4 - Update repositories"

Update-Repository -RepoPath $baseDir -RepoName "AnalyticsRepo (root)"
Update-Repository -RepoPath $gatewayDir -RepoName "gateway"

# -- Step 2: Gateway (nginx + auth-service + mongo) --
Write-Step "Step 2/4 - Start Gateway"

if (-not (Test-Path $gatewayDir)) {
    Write-Fail "Gateway directory not found: $gatewayDir"
    Exit 1
}

$gatewayOk = Start-DockerService -ServicePath $gatewayDir -ServiceName "gateway"
if (-not $gatewayOk) {
    Write-Fail "Gateway failed to start - aborting (other services depend on it)"
    Exit 1
}

Wait-ForHealthy -ContainerName "gateway-nginx-1" -TimeoutSeconds 60
Wait-ForHealthy -ContainerName "gateway-auth-service-1" -TimeoutSeconds 60

# -- Step 3: Gateway sub-services --
Write-Step "Step 3/4 - Start gateway sub-services"

$monitoringDir = Join-Path $gatewayDir "monitoring-service"
Start-DockerService -ServicePath $monitoringDir -ServiceName "monitoring-service"

$notificationDir = Join-Path $gatewayDir "notification-service"
Start-DockerService -ServicePath $notificationDir -ServiceName "notification-service"

Start-Sleep -Seconds 3

# -- Step 4: Application services --
Write-Step "Step 4/4 - Start application services"

$clientPath = Join-Path $baseDir "client_service"
$apartmentPath = Join-Path $baseDir "apartment_finder"
$referalPath = Join-Path $baseDir "referal"

$appServices = @(
    @{ Name = "client_service";   Path = $clientPath },
    @{ Name = "apartment_finder"; Path = $apartmentPath },
    @{ Name = "referal";          Path = $referalPath }
)

foreach ($svc in $appServices) {
    if (Test-Path $svc.Path) {
        Start-DockerService -ServicePath $svc.Path -ServiceName $svc.Name
    }
    else {
        Write-Info "$($svc.Name) - directory not found, skipping"
    }
}

# ----------------------------------------
# Summary
# ----------------------------------------

$elapsedTime = (Get-Date) - $startTime

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  SUMMARY"                                    -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  Time: $($elapsedTime.Minutes)m $($elapsedTime.Seconds)s" -ForegroundColor White

if ($succeededServices.Count -gt 0) {
    Write-Host "  OK ($($succeededServices.Count)):" -ForegroundColor Green
    foreach ($s in $succeededServices) {
        Write-Host "    + $s" -ForegroundColor Green
    }
}

if ($failedServices.Count -gt 0) {
    Write-Host "  FAILED ($($failedServices.Count)):" -ForegroundColor Red
    foreach ($s in $failedServices) {
        Write-Host "    - $s" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== RUNNING CONTAINERS ===" -ForegroundColor Cyan
$fmt = 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
docker ps --format $fmt

if ($failedServices.Count -gt 0) {
    Write-Host ""
    Write-Host "WARNING: Some services failed to start! Check logs above." -ForegroundColor Red
    Exit 1
}

Write-Host ""
Write-Host "All services started successfully!" -ForegroundColor Green
