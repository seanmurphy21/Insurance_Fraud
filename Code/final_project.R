# load packages
library(dplyr)
library(caret)
library(ggformula)
library(ggplot2)
library(readr)
library(xgboost)
library(nnet)
library(corrplot)
library(tidyverse)
library(pROC)

# read in the vehicle insurance fraud dataset
fraud <- read_csv('fraud_oracle.csv')

# examine the structure of the data
str(fraud)

# examine missingness
sum(is.na(fraud))

# check out row with missing DayOfWeekClaimed and MonthClaimed entries (as '0')
fraud[fraud$DayOfWeekClaimed == 0,]
# since it is one row and reasonable guesses cannot be made, remove the row
fraud <- fraud[fraud$DayOfWeekClaimed != 0,]

# examine distribution of Age
fraud %>%
  gf_histogram(~Age, fill = 'blue') %>%
  gf_labs(title = 'Many missing values encoded as 0',
          y = 'Count')
# many ages are 0, indicating that they are missing

# view the proportion of entries in the data frame with age equal to 0
dim(fraud[fraud$Age == 0,])[1] /dim(fraud)[1]

# since this is just around 2 percent of rows, we will drop these rows
fraud <- fraud[fraud$Age != 0,]

# now age has a more prominent right skew
fraud %>%
  gf_histogram(~Age, fill = 'blue') %>%
  gf_labs(title = 'Age is positively skewed',
          y = 'Count')

# log transform Age column and remove the original
fraud <- fraud %>%
  mutate(log_Age = log(Age)) %>%
  dplyr::select(-Age)

# remove PolicyNumber column from the data frame (unique identifier column)
fraud <- fraud %>%
  dplyr::select(-PolicyNumber) %>%
# convert all character columns to factors
  mutate_if(is.character, as.factor) %>%
# convert the appropriate numeric columns to factors
  mutate_at(c('WeekOfMonth', 'WeekOfMonthClaimed', 'FraudFound_P', 'RepNumber',
              'DriverRating', 'Deductible', 'Year'), as.factor)
# view the updated data structure
str(fraud)

# explore the effect of the time dimensions on fraud
source('conditional_bar.R')
time_dimensions <- c('Month', 'WeekOfMonth', 'DayOfWeek', 'DayOfWeekClaimed',
                     'MonthClaimed', 'WeekOfMonthClaimed')
par(mfrow = c(3,2))
for(ii in 1:6){
  print(conditional_bar(time_dimensions[ii], 'FraudFound_P', fraud))
}

# to reduce dimensions, drop day/date features which do not seem to affect fraud much
# also drop PolicyType column which is perfectly correlated with BasePolicy
fraud <- fraud %>%
  dplyr::select(-Month, -WeekOfMonth, -DayOfWeek, -DayOfWeekClaimed,
                -MonthClaimed, -WeekOfMonthClaimed, -PolicyType)

# see if the response is imbalanced
fraud %>%
  gf_props(~FraudFound_P, fill =~ FraudFound_P) %>%
  gf_labs(title = 'Highly Imbalanced Dataset',
          subtitle = 'Proportionally few cases of fraud',
          x = 'Fraud Found',
          y = 'Proportion') +
  labs(fill = 'Fraud Found')

# ensure enough expected fraud observations in each fold for 5-fold CV
(dim(fraud[fraud$FraudFound_P==1,])[1]/5) * .8 # 20% will be in a holdout set

# create a conditional bar graph to examine fraud against base policy
source('conditional_bar.R')
conditional_bar('BasePolicy', 'FraudFound_P', fraud) %>%
  gf_labs(title = 'Liability policies have lowest fraud rates',
          x = 'Base Policy',
          y = 'Proportion') +
  labs(fill = 'Fraud Found')

# create a conditional bar graph to examine fraud against AgentType
source('conditional_bar.R')
conditional_bar('AgentType', 'FraudFound_P', fraud) %>%
  gf_labs(title = 'Fraud proportion higher with external agents',
          x = 'Agent Type',
          y = 'Proportion') +
  labs(fill = 'Fraud Found')

# create a conditional bar graph to examine fraud against fault
source('conditional_bar.R')
conditional_bar('Fault', 'FraudFound_P', fraud) %>%
  gf_labs(title = 'Fraud proportion higher when policyholder is at fault',
          x = 'Party at Fault',
          y = 'Proportion') +
  labs(fill = 'Fraud Found')

# create a conditional bar graph to examine fraud against AgeOfPolicyHolder
source('conditional_bar.R')
conditional_bar('AgeOfPolicyHolder', 'FraudFound_P', fraud) %>%
  gf_labs(title = 'Conditional probability of fraud higher for policy holder ages 25 and under',
          x = 'Age of Policy Holder',
          y = 'Proportion') +
  labs(fill = 'Fraud Found')

# explore the effect of the dimensions with high numbers of categories
source('conditional_bar.R')
manycat_dimensions <- c('Make', 'RepNumber', 'AgeOfVehicle', 'AgeOfPolicyHolder',
                        'VehiclePrice', 'Days_Policy_Accident',
                        'AddressChange_Claim','NumberOfCars')
par(mfrow = c(4,2))
for(ii in 1:8){
  print(conditional_bar(manycat_dimensions[ii], 'FraudFound_P', fraud))
}

# from the above plots, it is clear we should drop RepNumber, AgeOfVehicle, and
# NumberOfCars since they do not appear to drastically impact fraud rates
fraud <- fraud %>%
  dplyr::select(-RepNumber, -AgeOfVehicle, -NumberOfCars) %>%
  # We can simplify AgeOfPolicyHolder to binary; policy holders under 26 seem
  # to have higher fraud rates
  mutate(AgeOfPolicyHolder = factor(ifelse(AgeOfPolicyHolder %in% c('18 to 20', '21 to 25'),
                                    '25 and under', 'over 25')),
         # since luxury brands seem to have different fraud rates, simplify Make to binary
         Luxury = factor(ifelse(Make %in% c('Accura', 'BMW', 'Ferrari', 'Jaguar',
                                            'Lexus', 'Mecedes', 'Porche'), '1', '0')),
         # cut VehiclePrice into three categories
         VehiclePrice = factor(case_when(VehiclePrice %in% c('less than 20000') ~ 'under 20000',
                                  VehiclePrice %in% c('60000 to 69000', 'more than 69000') ~ 'over 60000',
                                  TRUE ~ '20000 to 60000')),
         # make Days_Policy_Accident binary
         Days_Policy_Accident = factor(ifelse(Days_Policy_Accident == 'none', 'none', 'more than 1')),
         # make AddressChange_Claim binary
         AddressChange_Claim_Under6Months = factor(ifelse(AddressChange_Claim == 'under 6 months',
                                                   '1', '0'))) %>%
  dplyr::select(-Make, -AddressChange_Claim) # get rid of Make feature and original AddressChange_Claim feature

# identify other unimportant features to drop to improve runtime and make model simpler
unexplored_dimensions <- c('AccidentArea', 'Sex', 'MaritalStatus', 'VehicleCategory',
                           'Deductible', 'DriverRating', 'Days_Policy_Claim',
                           'PastNumberOfClaims', 'PoliceReportFiled', 'WitnessPresent',
                           'NumberOfSuppliments', 'Year')
source('conditional_bar.R')
par(mfrow = c(3,4))
for(ii in 1:12){
  print(conditional_bar(unexplored_dimensions[ii], 'FraudFound_P', fraud))
}

# based on the above, make PastNumberOfClaims binary and drop select rows
fraud <- fraud %>%
  mutate(PastClaimMade = factor(ifelse(PastNumberOfClaims == 'none',
                                       '0', '1'))) %>%
  dplyr::select(-DriverRating, -NumberOfSuppliments, -Year, -PastNumberOfClaims)

# scale log_Age and remove original, change labels for the response to 'yes' and 'no'
# for model training
fraud <- fraud %>%
  mutate(log_Age_scaled = scale(log_Age),
         FraudFound_P = factor(ifelse(FraudFound_P=='0', 'no', 'yes'))) %>%
  dplyr::select(-log_Age)

str(fraud)

### WILL BE COMPARING NEURAL NETS (1 HIDDEN LAYER), RADIAL SVMs, XGBOOST, AND LOGISTIC REGRESSION
# reserve a holdout set for outer layer of validation
set.seed(1)
n <- dim(fraud)[1]
n_train <- round(.8 * n)
n_test <- n - n_train
groups <- append(rep(1, length = n_train),rep(2, length = n_test))
groups_assigned <- sample(groups, n)
in_holdout <- (groups_assigned == 2)
training <- fraud %>%
  filter(!in_holdout)
holdout <- fraud %>%
  filter(in_holdout)

# Cohen's Kappa will be used as the metric to compare models because of imbalanced dataset
# set up trainControl method
ctrl <- trainControl(method = 'cv', number = 5)
# logistic regression
logit <- train(FraudFound_P ~ .,
               data = training,
               method = 'glm',
               family = 'binomial',
               metric = 'Kappa',
               trControl = ctrl)

# identify good starting values for XGBoost tuning parameters
# begin with number of trees at 100
n_trees <- 100
# test six values of tree depth
max_depth <- c(1,5,10,20,30,40)
# begin with moderate learning rate
eta <- 0.3
# start without pruning
gamma <- 0
# start with small min_child_weight
min_child_weight <- 1
# use a lower sample of predictors for each tree since there are many predictors
colsample <- 0.5
# start with all rows used by each tree, not too many observations
subsample <- 1

# XGBoost
xgboost <- train(FraudFound_P ~ .,
                 data = training,
                 method = 'xgbTree',
                 metric = 'Kappa',
                 trControl = ctrl,
                 verbosity = 1,
                 tuneGrid = expand.grid(nrounds = n_trees, max_depth = max_depth,
                                        eta = eta, gamma = gamma, colsample_bytree = colsample,
                                        min_child_weight = min_child_weight, subsample = subsample))

# identify good starting values for tuning parameters in SVMs
# start with cost values 0.01, 1, and 100
cost <- 10^(seq(-2,2,2))
# start with small range of sigma vals for radial SVM
sigma_radial <- c(.5,3)

# radial SVM
radial_svm <- train(FraudFound_P ~ .,
                    data = training,
                    method = 'svmRadial',
                    trControl = ctrl,
                    tuneGrid = expand.grid(C = cost,
                                           sigma = sigma_radial),
                    prob.model = TRUE,
                    metric = 'Kappa',
                    verbose = 1)

# identify good starting values for neural net tuning parameters
# input layer size is 27 (due to lots of categorical predictors)
# node range from 1-27, start at low end of range
num_nodes <- c(1,5,20)
decay <- 10^(seq(-3,1,2)) # 10 raised to sequential powers, max of 10

# neural net
neural_net <- train(FraudFound_P ~ .,
                    data = training,
                    method = 'nnet',
                    trControl = ctrl,
                    maxit = 2000,
                    trace = FALSE,
                    metric = 'Kappa',
                    tuneGrid = expand.grid(size = num_nodes, decay = decay))

# best model is XGBoost based on Cohen's Kappa
best_model <- xgboost

# create a confusion matrix for each best model predicting the holdout set
logit_conf_mat <- table(predict(logit, holdout), holdout$FraudFound_P)
xgboost_conf_mat <- table(predict(xgboost, holdout), holdout$FraudFound_P)
radial_svm_conf_mat <- table(predict(radial_svm, holdout), holdout$FraudFound_P)
neural_net_conf_mat <- table(predict(neural_net, holdout), holdout$FraudFound_P)

# define a function to return the accuracy, recall, precision, f1_score and Cohen's Kappa for a confusion matrix
classification_summary <- function(conf_mat){
  TN <- conf_mat[1]
  FP <- conf_mat[2]
  FN <- conf_mat[3]
  TP <- conf_mat[4]
  n <- TP + FP + TN + FN
  Po <- (TP + TN) / n
  Pe <- (((FP + TP) / n) * ((FN + TP) / n)) + (((TN + FN) / n) * ((TN + FP) / n))
  accuracy <- (TP + TN) / n
  precision <- TP / (TP + FP)
  recall <- TP / (TP + FN)
  F1_score <- (2 * precision * recall) / (precision + recall)
  Kappa <- (Po - Pe) / (1 - Pe)
  return(c(accuracy, precision, recall, F1_score, Kappa))
}

# examine the accuracy, precision, recall, F1 score, and Cohen's Kappa of all the best models on holdout data
classification_summary(logit_conf_mat);
classification_summary(xgboost_conf_mat);
classification_summary(radial_svm_conf_mat);
classification_summary(neural_net_conf_mat)

# set up roc curves for each of the models
roc_logit <- roc(holdout$FraudFound_P, predict(logit, holdout, type = 'prob')[,2])
roc_xgboost <- roc(holdout$FraudFound_P, predict(xgboost, holdout, type = 'prob')[,2])
roc_radial_svm <- roc(holdout$FraudFound_P, predict(radial_svm, holdout, type = 'prob')[,2])
roc_neural_net <- roc(holdout$FraudFound_P, predict(neural_net, holdout, type = 'prob')[,2])
auc_logit <- auc(holdout$FraudFound_P, predict(logit, holdout, type = 'prob')[,2])
auc_xgboost <- auc(holdout$FraudFound_P, predict(xgboost, holdout, type = 'prob')[,2])
auc_radial_svm <- auc(holdout$FraudFound_P, predict(radial_svm, holdout, type = 'prob')[,2])
auc_neural_net <- auc(holdout$FraudFound_P, predict(neural_net, holdout, type = 'prob')[,2])
par(mfrow = c(1,5))
ggroc(list(roc_logit, roc_xgboost, roc_radial_svm, roc_neural_net)) +
  scale_color_manual(labels = c(paste0('Logit Model AUC = ',paste(round(auc_logit,3))),
                                paste0('XGBoost Model AUC = ',paste(round(auc_xgboost,3))),
                                paste0('Radial SVM Model AUC = ',paste(round(auc_radial_svm,3))),
                                paste0('Neural Net Model AUC = ',paste(round(auc_neural_net,3)))),
                     values = c('red', 'orange', 'blue', 'violet'),
                     name = 'Model Type') +
  labs(title = 'Logistic Regression and XGBoost perform similarly on holdout data',
       x = 'Specificity',
       y = 'Sensitivity')

### generate plot of important variables against probability of fraud holding other variables
### constant at representative values

# credit to https://stackoverflow.com/questions/2547402/how-to-find-the-statistical-mode for this
# function finds the mode of a categorical variable
find_mode <- function(x) {
  ux <- unique(x)
  ux[which.max(tabulate(match(x, ux)))]
}
# generate example data
example_data <- fraud %>%
  mutate(across(where(is.factor) & c(-FraudFound_P, -Fault), find_mode))
# add the predicted probabilities
example_data <- example_data %>%
  mutate(predicted_probs = predict(xgboost, example_data, type = 'prob')[,2])
# generate the plot
example_data %>%
  gf_point(predicted_probs~log_Age_scaled, color =~ Fault, alpha = 0.6) %>%
  gf_labs(title = 'Predicted probability of fraud for representative values of log age and fault',
          subtitle = 'All other variables held constant at their modes',
          x = 'Scaled Log of Age',
          y = 'Predicted Probability of Fraud')

# since we used a holdout set for outer validation, fit the final model to the whole data set
final_model <- train(FraudFound_P ~ .,
                     data = fraud,
                     method = 'xgbTree',
                     trControl = trainControl(method = 'none'),
                     verbosity = 1,
                     tuneGrid = expand.grid(nrounds = n_trees, max_depth = 20, # best depth was 20
                                            eta = eta, gamma = gamma, colsample_bytree = colsample,
                                            min_child_weight = min_child_weight, subsample = subsample))

# grab the variable importances for the final model
var_imp_df <- rownames_to_column(varImp(final_model)$importance, var = 'Predictor')
# plot the top five importances
var_imp_df[1:5,] %>%
  gf_col(Overall~factor(Predictor, levels = c('log_Age_scaled',
                                              'FaultThird Party',
                                              'BasePolicyLiability',
                                              'VehicleCategorySport',
                                              'Deductible500')), fill = 'blue',
                        alpha = 0.6) %>%
  gf_labs(title = 'Most Important Predictors in Final Model',
          subtitle = 'Log of age and third party at fault are most important',
          x = 'Predictor',
          y = 'Importance')