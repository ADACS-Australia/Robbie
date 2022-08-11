## Installation

Robbie relies on 3 core technologies to run:
- nextflow
- python
- docker or singularity containers (optional)

### Nextflow

Nextflow can be installed in a few ways:
- By following instructions at [nextflow.io](https://www.nextflow.io/docs/latest/getstarted.html)
  - `wget -qO- https://get.nextflow.io | bash`
- By using a packaged manager such as [Conda](https://docs.conda.io/projects/conda/en/latest/user-guide/install/index.html):
  - `conda install -c bioconda nextflow`
- If you are using Pawsey you can just run:
  - `module load nextflow`

### Robbie scripts
The Robbie scripts are all bundled as a python package which can be downloaded and installed via github.

Using pip: `pip install https://github.com/ADACS-Australia/Robbie.git`

Using Conda: `conda install git pip` (and then run the above)

### Docker containers

#### Robbie base container
The best way to use Robbie is via a docker container that has all the software dependencies installed. Ensure docker is running, then build the container using:

``` bash
docker build -t paulhancock/robbie-next -f docker/Dockerfile .
```

or by pulling the latest build from [DockerHub](https://hub.docker.com/r/paulhancock/robbie-next) via

``` bash
docker pull paulhancock/robbie-next
```

Please see [Quickstart](quickstart) on how to run Robbie once the setup is complete.

#### Robbie visualisation container

To construct the Docker image for visualisation of the Robbie results, run the following:

``` bash
./build_docker.sh
``` 

within the ``robbie_viewer_server`` directory. Please see [Visualisation](visualisation) on how to visualise the results of Robbie using the aforementioned Docker image.

### Alternative when not using containers
If cannot, or chose not to, use containers then you will need to ensure that the Robbie scripts are available on your local machine.

Python dependencies can be installed via:
```
pip install -r requirements.txt
```

[Stils/TOPCAT](http://www.star.bris.ac.uk/~mbt/topcat/) needs to be downloaded and available on your machine.
Once the `.jar` file has been copied to your machine you need to edit `nextflow.config` and set the following parameter so that Robbie knows how to invoke stilts:
```
params.stilts = 'java -jar /path/to/topcat-full.jar -stilts'
```
Alternatively the above can be set from the command line using the `--stilts` argument.


[SWarp](https://www.astromatic.net/software/swarp/) can be installed via source or rpm as per the website description.
After installing you should be able to invoke SWarp using the command line `SWarp`.
If this is not the case, and you need a different command to use SWarp then edit the following parameter so that Robbie knows how to invoke SWarp:
```
params.swarp = <swarp command>
```
Alternatively the above can be set from the command line using the `--swarp` argument.

## Working with Robbie on Pawsey
Robbie is already installed and available on Pawsey / Garrawarla.

### Garrawarla
Robbie is installed as a module within the mwa group software stack.
To access robbie you should run:
``` bash
module load nextflow
module use /pawsey/mwa/software/python3/modulefiles/
module load robbie
```
Now you can run robbie by typing `robbie.nf` from the command line.

### Setonix
TBD when the mwa project groups (mwasci in particular) are migrated onto Setonix.

## Setting up robbie on a new hpc or cluster
The file `nextflow.config` contains all the information about how to run on different environments which are referred to as executors.
The default executor is `local` which means to run on the current machine, which is what you would do on your desktop/laptop.
In order to work on an hpc cluster you'll need to set the `executor` to be `slurm` or `pbs` or whatever it is your hpc uses to schedule jobs.
The Pawsey hpc clusters all use `slurm`.

Nextflow allows you to set 'profiles' within the `nextflow.config` which will let a user easily choose a whole bunch of settings without needing to update the configuration file.
These profiles can be selected by using `-profile <name>` from the command line when invoking your `Robbie.nf` script.

Currently, Robbie has been set up with profiles for Magnus, Zeus, and Garrawarla.
The Magnus and Zeus profiles need to be selected manually using `-profile Mangus` or `-profile Zeus`.
The Garrawarla profile doesn't need to be specified as it will automatically be set if Robbie sees that you are running on a machine with a hostname that starts with `garrawarla` (eg, one of the login nodes).

If you want to use Robbie on a different cluster or hpc, you'll need to create a profile in the `nextflow.config` file.
The best way to do this is to copy/paste from a different profile, and then refer to the [Nextflow documentation](https://www.nextflow.io/docs/latest/config.html) to understand what each parameter is doing, and what needs to be changed for your system.