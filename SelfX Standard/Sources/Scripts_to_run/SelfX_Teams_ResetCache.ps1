$Teams_Classic_Path = Join-Path $env:APPDATA "Microsoft\Teams"
$New_Teams_Cache_Path = Join-Path $env:LOCALAPPDATA "Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams"

$Teams_Process_Status = gwmi win32_process | where {$_.Name -like "*teams*"}
If($Teams_Process_Status -ne $null)	
	{
		$Teams_Path = $Teams_Process_Status.Path		
		try
			{
				$Teams_Process_Status.Terminate() | out-null	
				$Teams_Kill_Status = $True
			}
		catch
			{
				$Teams_Kill_Status = $False			
			}		
	}	
	
Sleep 5

If(test-path $Teams_Classic_Path)
	{
		Get-ChildItem $Teams_Classic_Path -Directory | Where name -in ('application cache','blob storage','databases','GPUcache','IndexedDB','Local Storage','tmp') | ForEach{Remove-Item $_.FullName -Recurse -Force}
	}

If(test-path $New_Teams_Cache_Path)
	{
		Get-ChildItem -LiteralPath $New_Teams_Cache_Path -Force | Remove-Item -Recurse -Force
	}

Sleep 5

if ($Teams_Path) {
	Start-Process -FilePath $Teams_Path
}