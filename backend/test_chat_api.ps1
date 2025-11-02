# PowerShell script to test Chat API
# Usage: .\test_chat_api.ps1

$baseUrl = "http://localhost:8000"
$sessionId = [guid]::NewGuid().ToString()

Write-Host "=" -NoNewline -ForegroundColor Cyan
Write-Host ("=" * 69) -ForegroundColor Cyan
Write-Host "Testing Chat API" -ForegroundColor Yellow
Write-Host "=" -NoNewline -ForegroundColor Cyan
Write-Host ("=" * 69) -ForegroundColor Cyan

# Check server
Write-Host "`n🔄 Checking if server is running..." -ForegroundColor Gray
try {
    $response = Invoke-RestMethod -Uri "$baseUrl/" -Method Get
    Write-Host "✅ Server running: $($response.app)" -ForegroundColor Green
} catch {
    Write-Host "❌ Server not running! Start with:" -ForegroundColor Red
    Write-Host "   uvicorn app.main:app --reload --host 0.0.0.0 --port 8000" -ForegroundColor Yellow
    exit 1
}

Write-Host "`n📝 Session ID: $sessionId" -ForegroundColor Cyan

# Test messages
$messages = @(
    "I am feeling tired",
    "Something relaxing to help me focus",
    "Actually, I want energetic music!"
)

Write-Host "`n" -NoNewline
Write-Host "=" -NoNewline -ForegroundColor Cyan
Write-Host ("=" * 69) -ForegroundColor Cyan
Write-Host "Conversation Test:" -ForegroundColor Yellow
Write-Host "=" -NoNewline -ForegroundColor Cyan
Write-Host ("=" * 69) -ForegroundColor Cyan

foreach ($msg in $messages) {
    Write-Host "`n[USER] $msg" -ForegroundColor White
    
    $body = @{
        session_id = $sessionId
        message = $msg
        provider = "groq"
        include_music_context = $true
    } | ConvertTo-Json
    
    try {
        $response = Invoke-RestMethod -Uri "$baseUrl/chat/send" -Method Post -Body $body -ContentType "application/json" -TimeoutSec 30
        
        Write-Host "[BOT] $($response.message)" -ForegroundColor Cyan
        
        if ($response.mood) {
            Write-Host "   [MOOD] $($response.mood.ToUpper())" -ForegroundColor Magenta
        }
        
        if ($response.suggested_action -eq "search_mood") {
            Write-Host "   [ACTION] TRIGGER MUSIC SEARCH" -ForegroundColor Green
        }
        
    } catch {
        Write-Host "❌ Error: $_" -ForegroundColor Red
    }
    
    Start-Sleep -Milliseconds 500
}

# Get history
Write-Host "`n" -NoNewline
Write-Host "=" -NoNewline -ForegroundColor Cyan
Write-Host ("=" * 69) -ForegroundColor Cyan
Write-Host "Conversation History:" -ForegroundColor Yellow
Write-Host "=" -NoNewline -ForegroundColor Cyan
Write-Host ("=" * 69) -ForegroundColor Cyan

try {
    $history = Invoke-RestMethod -Uri "$baseUrl/chat/history/$sessionId" -Method Get
    Write-Host "`n✅ Found $($history.history.Count) messages" -ForegroundColor Green
    
    $i = 1
    foreach ($h in $history.history) {
        $icon = if ($h.role -eq "user") { "[USER]" } else { "[BOT]" }
        $color = if ($h.role -eq "user") { "White" } else { "Cyan" }
        $preview = if ($h.content.Length -gt 60) { $h.content.Substring(0, 60) + "..." } else { $h.content }
        Write-Host "`n$i. $icon $($h.role.ToUpper()): $preview" -ForegroundColor $color
        $i++
    }
} catch {
    Write-Host "❌ Error: $_" -ForegroundColor Red
}

# Cleanup
Write-Host "`n" -NoNewline
Write-Host "=" -NoNewline -ForegroundColor Cyan
Write-Host ("=" * 69) -ForegroundColor Cyan
Write-Host "Cleanup:" -ForegroundColor Yellow
Write-Host "=" -NoNewline -ForegroundColor Cyan
Write-Host ("=" * 69) -ForegroundColor Cyan

try {
    $response = Invoke-RestMethod -Uri "$baseUrl/chat/clear/$sessionId" -Method Delete
    Write-Host "`n✅ Conversation cleared" -ForegroundColor Green
} catch {
    Write-Host "❌ Error: $_" -ForegroundColor Red
}

Write-Host "`n" -NoNewline
Write-Host "=" -NoNewline -ForegroundColor Cyan
Write-Host ("=" * 69) -ForegroundColor Cyan
Write-Host "✅ Test completed!" -ForegroundColor Green
Write-Host "=" -NoNewline -ForegroundColor Cyan
Write-Host ("=" * 69) -ForegroundColor Cyan
