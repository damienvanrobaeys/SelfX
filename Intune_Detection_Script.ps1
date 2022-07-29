$Destination_folder = "$env:LOCALAPPDATA\SelfX"
If(test-path $Destination_folder)
	{
		EXIT 0
	}
Else
	{
		EXIT 1
	}