
# Predicting Vehicle Insurance Fraud

This is a machine learning project in R using classification models to detect fraudulent vehicle insurance claims.

## Highlights

### Who is at fault?

<img src="https://github.com/seanmurphy21/Insurance_Fraud/blob/main/Plots/fraud_fault.png?raw=true" width="700" height="390" />

- Instances of fraud prove to be much higher when the policy holder is the party at fault.

### Fitting the Models

<img src="https://github.com/seanmurphy21/Insurance_Fraud/blob/main/Plots/roc_curves.png?raw=true" width="650" height="390" />

- XGBoost and Logistic Regression perform similarly on holdout data, although cross-validation selects the XGBoost model as optimal during training.

### Interpreting Predictors

<img src="https://github.com/seanmurphy21/Insurance_Fraud/blob/main/Plots/variable_importance.png?raw=true" width="600" height="390" />

- Age and party at fault are identified as the two most important predictors of fraud in the data.

<img src="https://github.com/seanmurphy21/Insurance_Fraud/blob/main/Plots/predicted_probs_important_vars.png?raw=true" width="600" height="390" />

- Our model predicts a higher probability of fraud only for those claims in which the policyholder was the party at fault.


## Full Project Summary

View the full project executive summary here: [Full Project Executive Summary](https://github.com/seanmurphy21/Insurance_Fraud/releases/tag/v1)
