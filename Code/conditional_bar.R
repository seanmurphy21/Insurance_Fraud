### Credit to Professor Abra Brisbin for this code###

conditional_bar <- function(var1, var2, data){
  # Makes a conditional bar graph of variables var1 and var2.
  # var1 and var2 should be quoted column names in `data`.
  # var1 is used as the main grouping variable (denominator).
  
  library(dplyr)
  library(ggformula)
  
  denom_df = data.frame(table(data[[var1]]))
  denom_df <- denom_df %>%
    rename(denominator = Freq)
  
  numer_df = data.frame(table(data[[var1]], data[[var2]]))
  numer_df <- numer_df %>%
    rename(numerator = Freq)
  
  prop_df <- left_join(numer_df, denom_df)
  prop_df <- prop_df %>%
    mutate(proportion = numerator/denominator)
  
  gf_col(proportion ~ Var1, fill =~ Var2, position = position_dodge(), data = prop_df) %>%
    gf_labs(title = paste("Conditional probability of", var2, "given", var1))
}
