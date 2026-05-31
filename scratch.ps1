$PortainerURL = 'https://docker.ghome.it'
$Username = 'admin'
$Password = 'gianvitobleve'
$authBody = @{Username=$Username;Password=$Password} | ConvertTo-Json
$response = Invoke-RestMethod -Uri "$PortainerURL/api/auth" -Method Post -Body $authBody -ContentType 'application/json'
$TOKEN = $response.jwt
$headers = @{Authorization="Bearer $TOKEN"}

$disconnectBody1 = @{Container="autify-autify-db-1"; Force=$true} | ConvertTo-Json
$disconnectBody2 = @{Container="autify-autify-api-1"; Force=$true} | ConvertTo-Json

try {
    Invoke-RestMethod -Uri "$PortainerURL/api/endpoints/2/docker/networks/autify_default/disconnect" -Method Post -Headers $headers -Body $disconnectBody1 -ContentType 'application/json'
} catch {
    Write-Host "Errore disconnessione 1: $($_.Exception.Response)"
}

try {
    Invoke-RestMethod -Uri "$PortainerURL/api/endpoints/2/docker/networks/autify_default/disconnect" -Method Post -Headers $headers -Body $disconnectBody2 -ContentType 'application/json'
} catch {
    Write-Host "Errore disconnessione 2: $($_.Exception.Response)"
}

try {
    Invoke-RestMethod -Uri "$PortainerURL/api/endpoints/2/docker/networks/autify_default" -Method Delete -Headers $headers
    Write-Host "Rete eliminata."
} catch {
    Write-Host "Errore eliminazione rete: $($_.Exception.Response)"
}
