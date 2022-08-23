# pbstools
A collection of user-facing PBS convenience tools maintained by CSG

## Description
These tools help augment basic PBS Pro commands with capabilities desired by the NCAR user community. Currently, the following tools are included:

* **qinteractive** - a script to quickly generate an interactive session
* **qcmd** - a script that allows the user to run a command in an output-only (*but otherwise fully functional*) shell

The qinteractive script is also linked as `execcasper`, a variant that targets Casper by default.

## Installation

Simply clone this repository and add the tools to the users' PATH via some mechanism (e.g., an environment module).
```
git clone https://github.com/NCAR/pbstools.git
```

## Adding Systems
System configurations are provided in the `etc` subdirectory of this repository. See the existing configurations for reference. The names provided in there will be used by the tools when "@" syntax is provided by the user. For example:
```
qinteractive -q main@gust
```
would use settings in a file called `etc/gust.conf`. It is recommended that you provide both short-form names and the explicit scheduler server name as options, likely via symbolic links.
