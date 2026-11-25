---
title: Note on the data
jupyter: python3
---


The datasets `data_1835.parquet` and `data_1840.parquet` are derived from historical Icelandic census data, and contain data from 1835 and 1840 respectively. 

The data are slightly altered versions of datasets collated and made available by the [ICE-ID 2.0 project](https://github.com/IIIM-IS/ICE-ID-2.0) and licensed as [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.en). There is more information about available from [this paper](https://arxiv.org/html/2506.13792v2).


* The data provide a realistic picture of what many real-world datasets are like.
* There has been a process of manual linking across time and some of the records have person identifiers providing a level of "ground truth"
* The data are public, and not subject to any onerous usage or privacy restrictions (which is rare for interesting record linkage datasets).

In this workshop the plan is to get right into the linking. In practical data linking projects, having a good data cleaning pipeline is crucial. It's useful to attend to things like:

* Basic data-cleaning operations like removing extraneous whitespace and punctuation from string fields and ensuring that missing values are recorded as `null` rather than a special string value like "unknown" or "missing" or a numeric code.
* Adding a field for standardised name so that "Bill" can match to "William" even though they are not close in terms of Jaro-Winkler similarity.
* Canonicalising addresses so that we aren't defeated by trivial variations in how addresses are represented across datasets.
* For splink, it's important to have an id column called `unique_id` and to make sure that variables have consistent names across datasets.


## Basic Setup

Run the first code cell to confirm that you're ready to follow along in the notebook. You should have splink version 5 and ideally duckdb version 2.0 (although older versions of duckdb will work).

```{python}
import splink 
import duckdb
print(f"The installed splink version is {splink.__version__}")
print(f"The installed duckdb version is {duckdb.__version__}")
```

```{python}
from splink import DuckDBAPI
import duckdb 

con = duckdb.connect('basic_linkage.duckdb')

df_l = con.from_parquet('data_1835.parquet')
df_r = con.from_parquet('data_1840.parquet')
```

```{python}
df_l.count("*")
```

We need to create a database API object to manage Splink's interactions with the backend. `sdf_l` and `sdf_r` are splink data frames, which let us work with tables used by splink in a way that is independent of the backend.

```{python}
db_api = DuckDBAPI(con) #SparkAPI for Spark etc
sdf_l = db_api.register(df_l)
sdf_r = db_api.register(df_r)
```

The best way to work with splink dataframes is usually to convert them to some more familiar format before further analysis:

* `sdf.as_pandas_dataframe()` converts splink data frame `sdf` to a pandas dataframe.
* `sdf.as_duckdbpyrelation()` converts splink data frame `sdf` to a duckdbpy relation.
* `sdf.to_csv('filename.csv')` and `sdf.to_parquet('filename.parquet')` save the data as csv and parquet respectively.

We can also run SQL queries on the Splink data frames directly, using `{this}` to refer to the database table represented by the data frame, e.g. 


* `sdf.query_sql("select * from {this} where age < 150")`

## Blocking

If two datasets have $n$ and $m$ and observations respectively, comparing every pair of records will involve comparisons. This becomes impractical before and even get very large. We need some way of cutting down the number of pairs of records to compare. Blocking means we only compare a pair of records if they agree exactly on a variable or group of variables.

Splink is quite flexible in how blocking rules can be specified (more on this later), but the main tool is splink.block_on, demonstrated below. When we provide a list of blocking rules of this form, a pair of records is compared if at least one of the rules is satisfied.

```{python}
from splink import DuckDBAPI, block_on
from splink.blocking_rule_library import CustomRule 


blocking_rules = [
    block_on('farm'),
    block_on('middle_name'),
    #CustomRule("jaro_winkler_similarity(l.first_name,r.first_name) > 0.8 and jaro_winkler_similarity(l.patronym,r.patronym) > 0.8",sql_dialect = 'duckdb'),
]
```

It's often useful to see how many comparisons each blocking rule is producing

```{python}
from splink.blocking_analysis import (
    chart_comparisons_from_blocking_rules
)

chart_comparisons_from_blocking_rules(
    [sdf_l, sdf_r],
    blocking_rules=blocking_rules,
    link_type="link_only",
    record_sample_proportion = 1.0
)
```

It's also possible to use functions of variables in blocking: 

`block_on("substr(first_name,1,2)")`

Means comparing all pairs with the same first two letters. 

We also have the ability to provide custom SQL which gets interpolated into a `WHERE` claude in the appropriate place.

`CustomRule("l.zip_code = r.zip_code and l.first_name != 'nicholas'")` 

What happens if we try to use

`CustomRule("jaro_winkler_similarity(l.first_name,r.first_name) > 0.9 and jaro_winkler_similarity(l.last_name,r.last_name) > 0.9",sql_dialect = 'duckdb')`

[hint](https://en.wikipedia.org/wiki/Hash_join)

## Participation/Discussion

The blocking rules that I have in the notebook will miss a lot of matches - experiment with adding some. Try to cover everything that might plausibly be a match while keeping the total number of comparisons reasonable.

We don't have to try very hard here because the dataset is small!

# Comparisons

`Splink` provides three ways of setting up comparisons. In increasing order of flexibility these are:

* [`splink.comparison_library`](https://moj-analytical-services.github.io/splink/api_docs/comparison_library.html) provides functions for common cases. For example, `ForenameSurnameComparison` sets up a comparison for a name variable with levels accounting for the possibility of typographical errors and field swaps.
  * `ExactMatch` is very frequently useful: it sets up a comparison which either agrees or disagrees, with no intermediate levels.
* [`splink.comparison_level_library`](https://moj-analytical-services.github.io/splink/api_docs/comparison_level_library.html) provides a set of lower-level tools for combining comparison levels.
* [The internal representation of a comparison is a python dictionary. We can provide this dictionary directly, which is cumbersome but allows for maximum flexibility](https://moj-analytical-services.github.io/splink/api_docs/settings_dict_guide.html#comparisons). 

```{python}
import splink.comparison_library as cl
import splink.comparison_level_library as cll

first_name_comparison = cl.NameComparison("first_name", jaro_winkler_thresholds=[0.92, 0.88])
```

It can be useful to look at the underlying internal representation (and this demonstrates the format of dictionaries that we could provide directly)

```{python}
first_name_comparison.get_comparison('duckdb').as_dict()
```

```{python}
first_name_comparison_v2 = cl.CustomComparison(
    output_column_name = "first_name",
    comparison_levels = [
        cll.NullLevel('first_name'),
        cll.ExactMatchLevel("first_name"),
        cll.JaroWinklerLevel('first_name',0.92),
        cll.JaroWinklerLevel('first_name',0.88),
        cll.ElseLevel()
    ])
```

```{python}
import logging
import splink.comparison_library as cl
import splink.comparison_level_library as cll
from splink import DuckDBAPI, Linker, SettingsCreator, block_on

settings = SettingsCreator(
    link_type="link_and_dedupe",
    blocking_rules_to_generate_predictions=blocking_rules,
    comparisons=[
        cl.NameComparison("first_name", jaro_winkler_thresholds=[0.9]).configure(term_frequency_adjustments=True),
        cl.NameComparison("patronym", jaro_winkler_thresholds=[0.9]).configure(term_frequency_adjustments=True),
        cl.NameComparison("middle_name",jaro_winkler_thresholds = [0.9]).configure(term_frequency_adjustments=True),
        cl.ExactMatch("sex"),
        cl.CustomComparison(
        output_column_name="location",
        comparison_levels=[
            cll.NullLevel("district"),
            cll.ExactMatchLevel("farm"),
            cll.ExactMatchLevel("parish"),
            cll.ExactMatchLevel("county"),
            cll.ExactMatchLevel("district"),
            cll.ElseLevel(),
        ]),
        cl.ExactMatch("birthyear"),
        cl.ExactMatch('marriagestatus')
    ],
    retain_intermediate_calculation_columns=True,
    max_iterations=100
)

linker = Linker(
    [sdf_l, sdf_r],
    settings,
    log_level = logging.WARNING #logging.WARNING for less verbose output
)
```

## Parameter Estimation

We have three tasks:

* Estimate the probability that a randomly sampled pair of records is a match (this is the $\lambda$ parameter in the fastLink paper)
* Estimate the $u$ probabilities, which give the probability that a pair of records will have a certain level of agreement on a certain variable, conditional on them not being a match.
* Estimate the $m$ probabilities, which give the probability that a pair of records will have a certain level of agreement on a certain variable, conditional on them being a match.

## Estimating the probability that two random records match

* The final results are not extremely sensitive to this parameter; we are really looking for a reasonable ballpark estimate.
* This parameter can, in theory, be estimated using the EM algorithm but experience shows that doing this tends to produce poor estimates.
* Often we will have a pretty clear idea of the expected number of matches (e.g. if we have reason to believe that almost every record on one dataset is also present on the other dataset), and this can help guide estimation of this parameter.

```{python}
deterministic_rules = [
  block_on("first_name", "patronym","sex","farm")
]

linker.training.estimate_probability_two_random_records_match(deterministic_rules, recall=0.5)
```

## Estimating the u probabilities

This is the easiest of the parameter estimation steps because we can easily approximately sample from the set of pairs of nonmatching records: we just sample from the set of pairs, an overwhelming majority of which are nonmatches.

* We need to set a `max_pairs` value to limit the size of the sample used.
  * Splink will stop early if it has seen enough examples at each agreement level, so we don't pay much of a price if `max_pairs` is set higher than it needs to be.

```{python}
linker.training.estimate_u_using_random_sampling(max_pairs=1e8)
```

### Aside: saving models

We can save the settings object, including any estimated parameters. At this stage, the file will include the estimate for $\lambda$ and the $u$ probabilities.

This allows us to pick up the model as it existed at a certain point, and is useful for recording exactly how a linked dataset was produeced. It is also sometimes useful as a way to debug and diagnose problems.

```{python}
linker.misc.save_model_to_json('basic_model_with_u_probabilities.json',overwrite=True)
```

```{python}
linker_copy = Linker(
    [sdf_l,sdf_r],
    'basic_model_with_u_probabilities.json'
)
```

## Estimating the M Probabilities 

* We need to use blocking to cut down the number of comparisons
  * If we block using a variable, we can't estimate the $m$ parameters for that variable, so we need to use multiple blocking rules.
* Parameter estimates should be similar across different blocking rules as long as the conditional independence assumption is not too badly violated.
* We should be aiming for between 1% and 99% of pairs returned by a blocking rule to be matches (this is just a rule of thumb).
  * Sometimes it can be useful to break this rule! 
* There is also an option to use a random sample of pairs of records from within blocks (we generally don't do this).
* Unlike with blocking for the predictions, we don't particularly need every true match to appear in at least one blocking rule.

```{python}
blocking_rules_for_em = [
    block_on("birthyear","farm"),
    block_on("first_name","farm"),
    block_on("patronym","farm"),
    block_on("middle_name","parish"),
    block_on("first_name","middle_name","patronym")
]

chart_comparisons_from_blocking_rules(
    [sdf_l, sdf_r],
    blocking_rules=blocking_rules_for_em,
    link_type="link_only",
    record_sample_proportion = 1.0
)
```

```{python}
for br in blocking_rules_for_em:
    linker.training.estimate_parameters_using_expectation_maximisation(br)
```

## Understanding the parameter estimates visually

```{python}
linker.visualisations.match_weights_chart()
```

```{python}
linker.visualisations.m_u_parameters_chart()
```

```{python}
#| scrolled: true
#linker.training.estimate_m_from_label_column('true_person_id') #add in estimates using the manually-curated ground truth
linker.visualisations.parameter_estimate_comparisons_chart()
```

## Why has this gone wrong?

Think about the mechanics of the EM algorithm.

```{python}
training_rules_v2 = [
    block_on("middle_name","patronym","farm","birthyear","sex","marriagestatus"),
    block_on("first_name","patronym","farm","birthyear","sex","marriagestatus"),
    block_on("first_name","middle_name","farm","birthyear","sex","marriagestatus"),
    block_on("first_name","middle_name","patronym","birthyear","sex","marriagestatus"),
    block_on("first_name","middle_name","patronym","farm","sex","marriagestatus"),
    block_on("first_name","middle_name","patronym","farm","birthyear","marriagestatus"),
    block_on("first_name","middle_name","patronym","farm","birthyear","sex"),
]

linker_v2 = Linker(
    [sdf_l,sdf_r],
    settings="basic_model_with_u_probabilities.json",
    log_level = logging.WARNING
)

for br in training_rules_v2:
    linker_v2.training.estimate_parameters_using_expectation_maximisation(br)
```

```{python}
linker_v2.visualisations.m_u_parameters_chart()
```

```{python}
linker_v2.training.estimate_m_from_label_column('true_person_id')
linker_v2.visualisations.parameter_estimate_comparisons_chart()
```

## Things for discussion and experimentation

* Try to break the model - what happens if we add variables that severely break the conditional independence assumption?
* Can we see ways in which the comparisons could be improved?


## Predictions

```{python}
df_predict = linker_v2.inference.predict()
```

```{python}
clusters = linker_v2.clustering.cluster_pairwise_predictions_at_threshold(
    df_predict, threshold_match_probability=0.95
)
clusters.as_pandas_dataframe()
```

```{python}
linker_v2.visualisations.match_weights_histogram(df_predict)
```

```{python}
#linker.visualisations.tf_adjustment_chart("first_name")
```

```{python}
linker_v2.visualisations.comparison_viewer_dashboard(
    df_predict, "scv.html", True, 2
)

from IPython.display import IFrame
IFrame(src="./scv.html", width="100%", height=1200)
```

```{python}
linker_v2.evaluation.accuracy_analysis_from_labels_column("true_person_id", add_metrics=["f1"])
```

```{python}
linker_v2.evaluation.prediction_errors_from_labels_column(
    "true_person_id",
    include_false_negatives=True,
    include_false_positives=False
).as_pandas_dataframe()
```

