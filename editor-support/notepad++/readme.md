## Installation Instructions for Notepad++

### Language Definition:  
Copy flux.xml to %APPDATA%\Notepad++\userDefineLangs
  
Restart Notepad++
  
Go to Language → User Defined Language → Define your language...
  
Click Import and select the flux.xml file
  
### Function List:  
Open %APPDATA%\Notepad++\functionList.xml

Add the <association> and <parser> sections from `lang\functionList.xml`.

Restart Notepad++

### Auto-Completion:  
Copy the auto-completion file to %APPDATA%\Notepad++\plugins\APIs\flux.xml

In Notepad++, go to Settings → Preferences → Auto-Completion

Check "Enable auto-completion on each input"

Select "Function completion" and "Word completion"

### Optional - Add to langs.xml for file association: 
Edit %ProgramFiles%\Notepad++\langs.xml and add:

```xml
<Language name="flux" ext="fx" />
```