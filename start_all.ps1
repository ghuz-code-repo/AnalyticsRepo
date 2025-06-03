# Script to start all Docker Compose services, starting with gateway

# Base directory where all services are located
$baseDir = $PSScriptRoot
$processes = @()

Write-Host "=== STARTING GOLDEN HOUSE SERVICES ===" -ForegroundColor Cyan

# List all folders in the current directory
Write-Host "Finding all service directories..." -ForegroundColor Cyan
$allFolders = Get-ChildItem -Path $baseDir -Directory | Where-Object { $_.Name -ne ".git" }
Write-Host "Found the following service directories:" -ForegroundColor White
$allFolders | ForEach-Object { Write-Host "  - $($_.Name)" }

# Step 1: Start Gateway First
$gatewayDir = Join-Path -Path $baseDir -ChildPath "!gateway"
if (Test-Path $gatewayDir) {
    Write-Host "Starting Gateway first..." -ForegroundColor Green
    
    # Start gateway in the current window and wait
    Push-Location $gatewayDir
    Write-Host "Executing Docker Compose in Gateway directory..." -ForegroundColor Yellow
    docker compose up --build -d
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Gateway services started successfully!" -ForegroundColor Green
    } else {
        Write-Host "Failed to start Gateway. Check errors above." -ForegroundColor Red
        Pop-Location
        Exit 1
    }
    Pop-Location
    
    # Small wait to ensure gateway is ready before other services
    Start-Sleep -Seconds 3
} else {
    Write-Host "Gateway directory not found: $gatewayDir" -ForegroundColor Red
    Exit 1
}

function Update-Repository {
    param (
        [string]$folderPath,
        [string]$folderName
    )
    
    if (Test-Path (Join-Path -Path $folderPath -ChildPath ".git")) {
        Write-Host "Updating git repository in $folderName..." -ForegroundColor Yellow
        
        Push-Location $folderPath
        
        # Fetch the latest changes
        Write-Host "Running git fetch..." -ForegroundColor Yellow
        git fetch
        
        # Check for fetch errors
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Git fetch failed for $folderName" -ForegroundColor Red
            Pop-Location
            return $false
        }
        
        # Pull the latest changes
        Write-Host "Running git pull..." -ForegroundColor Yellow
        git pull
        
        # Check for pull errors
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Git pull failed for $folderName" -ForegroundColor Red
            Pop-Location
            return $false
        }
        
        Write-Host "Repository $folderName updated successfully!" -ForegroundColor Green
        Pop-Location
        return $true
    } else {
        Write-Host "$folderName is not a git repository, skipping update" -ForegroundColor Yellow
        return $true
    }
}

# Add this code before starting Gateway in your script
Write-Host "Updating Gateway repository..." -ForegroundColor Yellow
Update-Repository -folderPath $gatewayDir -folderName "Gateway"

function Update-Repository {
    param (
        [string]$folderPath,
        [string]$folderName
    )
    
    if (Test-Path (Join-Path -Path $folderPath -ChildPath ".git")) {
        Write-Host "Updating git repository in $folderName..." -ForegroundColor Yellow
        
        Push-Location $folderPath
        
        # Fetch the latest changes
        Write-Host "Running git fetch..." -ForegroundColor Yellow
        git fetch
        
        # Check for fetch errors
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Git fetch failed for $folderName" -ForegroundColor Red
            Pop-Location
            return $false
        }
        
        # Pull the latest changes
        Write-Host "Running git pull..." -ForegroundColor Yellow
        git pull
        
        # Check for pull errors
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Git pull failed for $folderName" -ForegroundColor Red
            Pop-Location
            return $false
        }
        
        Write-Host "Repository $folderName updated successfully!" -ForegroundColor Green
        Pop-Location
        return $true
    } else {
        Write-Host "$folderName is not a git repository, skipping update" -ForegroundColor Yellow
        return $true
    }
}

# Step 2: Start all other services in separate terminals
foreach ($folder in $allFolders) {
    # Skip the gateway folder since we already handled it
    if ($folder.Name -eq "!gateway") {
        continue
    }
    if ($folder.Name -eq ".vscode") {
        continue
    }
    $folderPath = $folder.FullName
    $folderName = $folder.Name
    
    Update-Repository -folderPath $folderPath -folderName $folderName

    # Check if docker-compose file exists
    $dockerComposeExists = (Test-Path -Path (Join-Path -Path $folderPath -ChildPath "docker-compose.yml")) -or 
                           (Test-Path -Path (Join-Path -Path $folderPath -ChildPath "docker-compose.yaml"))
    
    if (-not $dockerComposeExists) {
        Write-Host "No docker-compose file found in $folderName - skipping" -ForegroundColor Yellow
        continue
    }
    
    Write-Host "Starting service: $folderName" -ForegroundColor Green
    
    # Create a script block that will run and close when done
    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(@"
        Set-Location '$folderPath'
        Write-Host 'Starting Docker Compose for $folderName...'
        docker compose up --build -d
        if (`$LASTEXITCODE -eq 0) {
            Write-Host 'Docker Compose for $folderName completed successfully' -ForegroundColor Green
        } else {
            Write-Host 'Docker Compose for $folderName failed!' -ForegroundColor Red
            Read-Host 'Press Enter to exit'
        }
        # The terminal will auto-close after this command completes
"@))
    
    # Start the process and add it to our tracking array
    $process = Start-Process powershell -ArgumentList "-EncodedCommand", $encodedCommand -WindowStyle Normal -PassThru
    $processes += $process
    
    # Small pause between starting services
    Start-Sleep -Seconds 1
}

# Step 3: Wait for all processes to exit
Write-Host "Waiting for all service terminals to complete..." -ForegroundColor Cyan
foreach ($process in $processes) {
    Write-Host "Waiting for process ID: $($process.Id) to complete..." -ForegroundColor Yellow
    $process.WaitForExit()
    Write-Host "Process ID: $($process.Id) has exited." -ForegroundColor Green
}

Write-Host "All Docker Compose commands have completed!" -ForegroundColor Green

# Step 4: Show running containers
Write-Host "`n=== RUNNING CONTAINERS ===" -ForegroundColor Cyan
docker ps -a

Write-Host "`n=== ALL SERVICES STARTED ===" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to exit this script"

# Keep the main script running
try {
    while ($true) {
        Start-Sleep -Seconds 10
    }
} catch {
    Write-Host "Script terminated."
}