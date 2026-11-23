# agent-skills

## Installation

```bash
npx skills add ssh://git@ssh.github.com:443/serosme/agent-skills.git -a opencode -g -y

npx skills add ssh://git@ssh.github.com:443/antfu/skills.git --skill antfu-query --skill antfu-simplify -a opencode -g -y

mise use -g npm:agent-browser
npx skills add ssh://git@ssh.github.com:443/vercel-labs/agent-browser -a opencode -g -y

mise use -g npm:@dbx-app/cli
dbx agent setup

mise use -g gh
gh skill install cli/cli gh --agent universal --scope user
```
