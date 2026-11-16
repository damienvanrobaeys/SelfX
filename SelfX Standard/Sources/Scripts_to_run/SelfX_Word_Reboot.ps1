$Word_Process_Status = gwmi win32_process | where {$_.Name -like "*word*"}
If($Word_Process_Status -ne $null)	
	{
		$Word_Path = $Word_Process_Status.Path 
		try
			{
				$Word_Process_Status.Terminate() | out-null	
				$Kill_Status = $True
			}
		catch
			{
				$Kill_Status = $False			
			}		
	}
	
Sleep 10

If($Kill_Status -eq $True)
	{
		Start-Process -FilePath $Word_Path 	
	}