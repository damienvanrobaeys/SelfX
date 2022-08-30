$Destination_folder = "$env:LOCALAPPDATA\SelfX"
If(test-path $Destination_folder)
	{
		write-output "SelfX detected, exiting"	
		EXIT 0
	}Else{
		EXIT 1
	}