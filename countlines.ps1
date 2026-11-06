git ls-files | Where-Object { $_ -like '*.bv' -or $_ -like '*.rbv' } | ForEach-Object { (Get-Content $_).Count } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
