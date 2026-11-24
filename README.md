# Splink demos

This is a collection of demos for the probabilistic linking Python package [Splink](https://moj-analytical-services.github.io/splink/index.html). 

I have included some mock datasets to be used for practice, these are `perturbed_data_l.parquet` and `perturbed_data_r.parquet`. These are artificially generated and don't include any real data. The script for generating similar datasets is included here.

# Setup 

You will need Python installed, see here: https://www.python.org/downloads/

1. Clone this github repo to your computer, or simply download it as a zip file by going to Code > Download ZIP. Extract this to a folder somewhere you can find it.
2. Open the terminal (if on Windows, Powershell would work) and navigate to this folder, which usually looks like this `cd </path/to/the/folder>`.
3. Create a virtual environment called "venv": `python -m venv venv`.
4. Activate the environment, `.\venv\Scripts\activate` for Powershell, but maybe `source ./venv/bin/activate` for a Bash terminal (e.g. if you're using Mac or Linux)
5. Install the packages we need: Splink, pandas, and we will include the notebook package so we can use jupyter notebooks. Run `pip install splink pandas notebook`
6. You can now open jupyter by running `jupyter notebook`, and you should be able to run any of the notebooks.

