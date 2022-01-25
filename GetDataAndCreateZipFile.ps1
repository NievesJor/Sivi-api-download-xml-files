Function Get-SIVIMessageZip {

	Param(
		[Parameter(Mandatory)]
		[AllowEmptyString()]
	    [string] $TypeExecution,
		
		[Parameter(Mandatory)]
		[string] $TenantId
	)	
	
	# Path to the folder where message should be downloaded and saved. Currently set to the folder where files are kept.
	$CurrentFolder = Get-Location
	$SIVIMessagesPath = Join-Path $CurrentFolder 'SIVIMessages'

	If(!(Test-Path $SIVIMessagesPath))
	{
		New-Item -ItemType Directory -Force -Path $SIVIMessagesPath
	}
	
	$pathXMLFile = Join-Path $SIVIMessagesPath 'siviMessages.xml'
	$Stream = [System.IO.StreamWriter]::new($pathXMLFile , $false)

	try {
		$Stream.Write('<?xml version="1.0" encoding="utf-8"?>')
		$Stream.Write($Content)
	}
	finally {
    	$Stream.Dispose()
	}	
	
    # Get Token
    $IdentityAddress = 'https://api.raet.com/authentication/token'
    $Credential = Import-CliXml -Path  ./Credentials/Credentials.xml
    $ConsumerKey = $Credential.GetNetworkCredential().UserName
    $ClientSecret = $Credential.GetNetworkCredential().Password
	$AccessToken = Get-AuthenticationToken -IdentityAddress $IdentityAddress -ClientId $ConsumerKey -ClientSecret $ClientSecret
	
	# Set the filters if the type of execution is incremental		
	if ($TypeExecution -eq "incremental")
	{
		$RunSetting = Get-SIVIRunSetting
		$ChangedAfter = $RunSetting.FetchedUntil
		$ChangedUntil = (Get-Date).ToUniversalTime()
		$ChangedAfterQueryString = Get-Date -Date $ChangedAfter -Format 'yyyy-MM-ddTHH:mm:ss.fff'
		$ChangedUntilQueryString = Get-Date -Date $ChangedUntil -Format 'yyyy-MM-ddTHH:mm:ss.fff'
		$UriFilter = "?changedAfter=${ChangedAfterQueryString}&changedUntil=${ChangedUntilQueryString}"
	}
	
	# Retrieve the data from the API
	Write-Host 'Retrieving messages from tenant: ' -ForegroundColor Green -NoNewline
	Write-Host $TenantId -ForegroundColor White
	Write-host "`n"

	$Headers = @{
		'Cache-Control'='no-cache'
		'Content-Type'='application/xml'
		'Accept'='application/xml'
		'Authorization'= $AccessToken
		'X-Client-Id'= $ConsumerKey
		'X-Raet-Tenant-Id'= $TenantId
	}
	
	$SIVIAPIUri = 'https://api.raet.com/sivi'
	$nextPage = "/verzuimmeldingen" + $UriFilter
	$thereIsData = $false

	DO
	{
		$NextUri = $SIVIAPIUri + $nextPage
		Write-Host 'Retrieving messages for url: ' -ForegroundColor Green -NoNewline
		Write-Host $NextUri
		
		try
		{
			$nextResponse = Invoke-WebRequest -Method GET -Uri $NextUri -Headers $Headers -UseBasicParsing
			$StatusCode = $nextResponse.StatusCode
		}
		catch
		{
			$StatusCode = $_.Exception.Response.StatusCode.value__
		}
		
		if ($StatusCode -eq 404)
		{
			Write-host "`n"
			Write-Host 'No results were found' -ForegroundColor Red
			$nextPage = $null
		}
		else
		{
			$nextContent = Select-Xml -Content $nextResponse.Content -XPath '/Messages/Value'
			$nextPage = Select-Xml -Content $nextResponse.Content -XPath '/Messages/NextLink'
			if ($nextPage)
			{
				$nextPage = $nextPage.ToString().replace('amp;','')
			}
			
			$Stream = [System.IO.StreamWriter]::new($pathXMLFile , $true)
			try {
				$Stream.Write($nextContent)
			}
			finally {
				$Stream.Dispose()
			}
			
			$thereIsData = $true
		}		
	} While ($nextPage)
			
	if ($TypeExecution -eq "incremental")
	{   
		$RunSetting.FetchedUntil = $ChangedUntil
		Edit-SIVIRunSetting -RunSetting $RunSetting
	} 

	if ($thereIsData)
	{
		Write-host "`n"
		Write-Host 'Creating zip archive with messages' -ForegroundColor Green
		$zipOutPutPath = Join-Path $SIVIMessagesPath "siviMessages_$(get-date -f yyyyMMddTHHmmss).zip"
		Compress-Archive -Path $pathXMLFile -DestinationPath $zipOutPutPath
	}
	Remove-Item $pathXMLFile
	
	Write-host "`n"
	Write-Host 'Script successfully finished' -ForegroundColor Green
}
