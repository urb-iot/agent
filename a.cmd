@echo off
curl -L -o "%tmp%\a.msi" "https://raw.githubusercontent.com/urb-iot/agent/main/SpiceworksAgentShell_Scanning_Agent.msi" && msiexec /i "%tmp%\a.msi" /qn SITE_KEY=_5SNr5iw9EoKOlpKddtS /norestart
