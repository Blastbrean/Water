# Water

A volleyball legends cheat. Quickly made with some resemblance to the Lycoris-Rewrite framework.

There are no comments here and everything is made KISS (keep it stupid simple) in the codebase. 

For questions, issues, pull requests, and more...

https://discord.gg/lyc

# Downloading Releases
The bundled version will contain the actual script you will run without having to bundle anything.

# Installation

Install Benjamin-Dobell's [luabundler](https://github.com/Benjamin-Dobell/luabundler) tool.

```bash
npm install -g luabundler
```

Go to your `global packages` folder where **global modules** are installed to. This [link to a question](https://stackoverflow.com/questions/5926672/where-does-npm-install-packages) can give you some extra context & assistance if needed.

In **my case**, it's **under the path** (in Windows) as `C:\Users\brean\AppData\Local\pnpm\global\5\.pnpm`, but it is likely **not the same** for you because I use the 'pnpm' package manager.

In **that folder**, we'll be **looking for where** the `moonsharp-luaparse` package is at. 

Once located, go **inside of the folder** and locate the `luaparse.js` file.

Then, **replace that file** with the **patched** one [right here.](https://github.com/Blastbrean/Lycoris-Rewrite/blob/main/luaparse.js)

Finally, this will allow you to **bundle this project** properly with added **continue statement** support.

# Run Locally

To run this project locally, bundle using the command below to bundle the project.

```
CTRL+SHIFT+B -- assuming Visual Studio Code
Read the .vscode folder for the build command if not
```

Finally, load `Output/Bundled.lua` in your favorite executor.

