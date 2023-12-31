#' ---
#' title: "Class 4 live demo: Hidden Markov models and capture-recapture data"
#' author: "The team"
#' date: "last updated: `r Sys.Date()`"
#' output: html_document
#' ---
#' 
#' 
## ----setup, include=FALSE, echo=FALSE----------------------------------------------------------
options(htmltools.dir.version = FALSE)
knitr::opts_chunk$set(comment = "")
library(tidyverse)
theme_set(theme_light(base_size = 14))
update_geom_defaults("point", list(size = 2)) 
library(here)
library(nimble)

#' 
#' 
#' ## Introduction
#' 
#' In this demo, we introduce Markov models and hidden Markov models following up on the survival example. Now we'll be using longitudinal data, that is data collected over time on the same individuals. We will also briefly see how to simulate data. Simulating data often proves useful to better understand how your model works, check that you get the right answer by comparing the parameters you used to simulate the data and the estimates you get, and to communicate with others on the model hypotheses and limitations.
#' 
#' ## Markov chain 
#' 
#' Load some useful packages. 
## ----echo = TRUE, message=FALSE, warning=FALSE-------------------------------------------------
library(tidyverse)

#' 
#' We start with 57 individuals, and we monitor them over 5 occasions. 
## ----echo = TRUE, message=FALSE, warning=FALSE-------------------------------------------------
nind <- 57
nocc <- 5

#' 
#' For simplicity, we assume that we have a single cohort, that is all individuals enter the study at the same time, here on the first occasion. 
## ----echo = TRUE, message=FALSE, warning=FALSE-------------------------------------------------
first <- rep(1, nind) # single cohort

#' 
#' We set survival to 0.8, and define $z$ as a matrix with dimensions the number of individuals (rows) and the number of occasions (columns). 
## ----echo = TRUE, message=FALSE, warning=FALSE-------------------------------------------------
phi <- 0.8
z <- matrix(NA, nrow = nind, ncol = nocc)

#' 
#' Now we simulate the fate of all individuals over time. 
## ----echo = TRUE, message=FALSE, warning=FALSE-------------------------------------------------
for (i in 1:nind){ # loop over individuals
  z[i,first[i]] <- 1 # all individuals are alive at first occasion
  for (t in (first[i]+1):nocc){ # loop over time
    z[i,t] <- rbinom(1, 1, phi * z[i,t-1]) # if z[i,t-1] = 1, then z[i,t] ~ dbern(phi)
                                           # if z[i,t-1] = 0, then z[i,t] ~ dbern(0) = 0 (once you're dead, you remain dead)
  }
}

#' 
#' The zeros are replaced by twos to match the coding proposed in the lecture. One is for alive, two is for dead. 
## ----echo = TRUE, message=FALSE, warning=FALSE-------------------------------------------------
z[z==0] <- 2 # 2 = dead, 1 = alive

#' 
#' Name the columns. 
## ----echo = TRUE, message=FALSE, warning=FALSE-------------------------------------------------
colnames(z) <- paste0("winter ", 1:nocc)

#' 
#' Display the matrix $z$. 
## ----echo = TRUE, message=FALSE, warning=FALSE-------------------------------------------------
z %>% 
  as_tibble() %>% 
  add_column(id = 1:nind, .before = "winter 1") %>%
  kableExtra::kable() %>%
  kableExtra::scroll_box(width = "100%", height = "400px")

#' 
#' Now we're going to fit a Markov model to the data we've just simulated. We load nimble. 
## ----------------------------------------------------------------------------------------------
library(nimble)

#' 
#' Then we build the model. 
## ----------------------------------------------------------------------------------------------
markov.survival <- nimbleCode({
  phi ~ dunif(0, 1) # prior
  gamma[1,1] <- phi      # Pr(alive t -> alive t+1)
  gamma[1,2] <- 1 - phi  # Pr(alive t -> dead t+1)
  gamma[2,1] <- 0        # Pr(dead t -> alive t+1)
  gamma[2,2] <- 1        # Pr(dead t -> dead t+1)
  delta[1] <- 1          # Pr(alive t = 1) = 1
  delta[2] <- 0          # Pr(dead t = 1) = 0
  # likelihood
  for (i in 1:N){
    z[i,1] ~ dcat(delta[1:2])
    for (j in 2:T){
      z[i,j] ~ dcat(gamma[z[i,j-1], 1:2])
    }
  }})

#' ]
#' 
#' We put the constants in a list. 
## ----------------------------------------------------------------------------------------------
my.constants <- list(N = 57, T = 5)
my.constants

#' 
#' We put the data in a list. 
## ----------------------------------------------------------------------------------------------
my.data <- list(z = z)
my.data

#' 
#' We write a function that generates initial values for survival.
## ----------------------------------------------------------------------------------------------
initial.values <- function() list(phi = runif(1,0,1))
initial.values()

#' 
#' We specify that we'd like to monitor survival. 
## ----------------------------------------------------------------------------------------------
parameters.to.save <- c("phi")
parameters.to.save

#' 
#' Let's specify a few details about the chains. 
## ----------------------------------------------------------------------------------------------
n.iter <- 5000
n.burnin <- 1000
n.chains <- 2

#' 
#' And now, run nimble. 
## ---- message=FALSE, warning=FALSE, eval=TRUE--------------------------------------------------
mcmc.output <- nimbleMCMC(code = markov.survival, 
                          constants = my.constants,
                          data = my.data,              
                          inits = initial.values,
                          monitors = parameters.to.save,
                          niter = n.iter, 
                          nburnin = n.burnin, 
                          nchains = n.chains)

#' 
## ----------------------------------------------------------------------------------------------
library(MCMCvis)
MCMCsummary(mcmc.output, round = 2)

#' 
#' The posterior mean is close to the value of survival we used to simulate the data $\phi = 0.8$. Great! 
#' 
#' Note that you should be able to write the model in a more efficient way with matrices and vectors.
## ----eval = FALSE------------------------------------------------------------------------------
markov.survival <- nimbleCode({
  phi ~ dunif(0, 1) # prior
  gamma[1:2,1:2] <- matrix(c(phi, 0, 1 - phi, 1), nrow = 2)
  delta[1:2] <- c(1, 0)
  # likelihood
  for (i in 1:N){
    z[i,1] ~ dcat(delta[1:2])
    for (j in 2:T){
      z[i,j] ~ dcat(gamma[z[i,j-1], 1:2])
    }
  }})

#' ]
#' 
#' ## Hiden Markov chain
#' 
#' On top of the matrix of alive/dead states, we add the detection process. First we set the detection probability to $p = 0.6$. 
## ----------------------------------------------------------------------------------------------
p <- 0.6

#' 
#' Then we say for now that the matrix of detections and non-detections is just $z$ in which dead individuals are not detected. 
## ----------------------------------------------------------------------------------------------
y <- z
y[z==2] <- 0

#' 
#' Now for alive individuals, those for which $y = z = 1$, we say they're detected with probability 1. 
## ----------------------------------------------------------------------------------------------
y[y==1] <- rbinom(n = sum(y==1), 1, p)

#' 
#' Let's get the number of individuals that have at least a detection. 
## ----------------------------------------------------------------------------------------------
nobs <- sum(apply(y,1,sum) != 0)
nobs

#' 
#' Before going any further, we need to get rid of the `r nrow(z) - nobs` individuals that have never been detected. 
## ----------------------------------------------------------------------------------------------
y <- y[apply(y,1,sum)!=0, ]

#' 
#' Let's get the occasion of first capture for each individual.
## ----------------------------------------------------------------------------------------------
first <- apply(y, 1, function(x) min(which(x != 0)))

#' 
#' For convenience, we will replace the 0s before first detection by NAs.
## ----------------------------------------------------------------------------------------------
for (i in 1:nobs){
  if(first[i] > 1) y[i, 1:(first[i]-1)] <- NA
}
y %>%
  as_tibble() %>%
  add_column(id = 1:nobs, .before = "winter 1") %>%
  kableExtra::kable() %>%
  kableExtra::scroll_box(width = "100%", height = "300px")

#' 
#' Now we're ready to fit our HMM to the data we simulated. As usual, we first define the model.
## ----------------------------------------------------------------------------------------------
hmm.survival <- nimbleCode({
  phi ~ dunif(0, 1) # prior survival
  p ~ dunif(0, 1) # prior detection
  # likelihood
  gamma[1,1] <- phi      # Pr(alive t -> alive t+1)
  gamma[1,2] <- 1 - phi  # Pr(alive t -> dead t+1)
  gamma[2,1] <- 0        # Pr(dead t -> alive t+1)
  gamma[2,2] <- 1        # Pr(dead t -> dead t+1)
  delta[1] <- 1          # Pr(alive t = 1) = 1
  delta[2] <- 0          # Pr(dead t = 1) = 0
  omega[1,1] <- 1 - p    # Pr(alive t -> non-detected t)
  omega[1,2] <- p        # Pr(alive t -> detected t)
  omega[2,1] <- 1        # Pr(dead t -> non-detected t)
  omega[2,2] <- 0        # Pr(dead t -> detected t)
  for (i in 1:N){
    z[i,first[i]] ~ dcat(delta[1:2]) # initial state prob
    for (j in (first[i]+1):T){
      z[i,j] ~ dcat(gamma[z[i,j-1], 1:2]) # z_t given z_(t-1)
      y[i,j] ~ dcat(omega[z[i,j], 1:2])   # y_t given z_t
    }
  }
})

#' 
#' Then put the constants in a list. 
## ----------------------------------------------------------------------------------------------
my.constants <- list(N = nrow(y),      # nb of individuals
                     T = 5,            # nb of occasions
                     first = first)    # occasions of first capture
my.constants

#' 
#' Now the data in a list. Note that we add 1 to the data to have 1 for non-detections and 2 for detections. You may use the coding you prefer of course, you will just need to adjust the $\Omega$ and $\Gamma$ matrices in the model above.  
## ----------------------------------------------------------------------------------------------
my.data <- list(y = y + 1)

#' 
#' Specify initial values. For the latent states, we go for the easy way, and say that all individuals are alive throught the study period. 
## ----------------------------------------------------------------------------------------------
zinits <- y + 1 # non-detection -> alive
zinits[zinits == 2] <- 1 # dead -> alive
initial.values <- function() list(phi = runif(1,0,1),
                                  p = runif(1,0,1),
                                  z = zinits)

#' 
#' Specify the parameters we'd like to monitor. 
## ----------------------------------------------------------------------------------------------
parameters.to.save <- c("phi", "p")
parameters.to.save

#' 
#' MCMC detaisl. 
## ----------------------------------------------------------------------------------------------
n.iter <- 5000
n.burnin <- 1000
n.chains <- 2

#' 
#' At last, let's run nimble. 
## ---- message=FALSE, warning=FALSE-------------------------------------------------------------
mcmc.output <- nimbleMCMC(code = hmm.survival,               # model code 
                          constants = my.constants,          # constants
                          data = my.data,                    # data
                          inits = initial.values,            # initial values
                          monitors = parameters.to.save,     # parameters to monitor
                          niter = n.iter,                    # nb of iterations
                          nburnin = n.burnin,                # length of the burn-in period
                          nchains = n.chains)                # nb of chains

#' 
#' We display the results. The posterior means of detection and survival are close to the parameters we used to simulate the data. 
## ----------------------------------------------------------------------------------------------
library(MCMCvis)
MCMCsummary(mcmc.output, round = 2)

#' 
#' 
#' <!-- knitr::purl(here::here("worksheets","3_demo.Rmd"), documentation = 2) -->
#' 
