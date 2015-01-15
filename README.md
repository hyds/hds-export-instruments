hds-export-instruments
======================

This HYSCRIPT exports instrument records from Hydstra into a CSV for import to Karl's app.

## Version

Version 0.01

## Synopsis


## Parameter screen

![Parameter screen](/images/psc.png)

## INI configuration

![INI file](/images/ini.png)

## Workflow

The workflow pushes valid documents into the hydstra documents tree under the SITE directory, and creates new SITE folders if there are none currently. Invalid documents are pushed to a subfolder in the import folder to be manually corrected.

![Parameter screen](/images/workflow.png)
  
## Bugs

Please report any bugs in the issues wiki.

