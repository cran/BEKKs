#' Estimating multivariate volatility impulse response functions (VIRF) for BEKK models
#'
#' @description Method for estimating VIRFs of N-dimensional BEKK models. Currently, only VIRFs for symmetric BEKK models are implemented.
#'
#' @param x An object of class "bekkfit" from function \link{bekk_fit}.
#' @param time Time instance to calculate VIRFs for.
#' @param q A number specifying the quantile to be considered for a shock on which basis the VIRFs are generated.
#' @param index_series An integer defining the number of series for which a shock is assumed.
#' @param n.ahead An integer defining the number periods for which the VIRFs are generated.
#' @param ci A number defining the confidence level for the confidence bands.
#' @param time_shock Boolean indicating if the estimated residuals at date specified by "time" shall be used as a shock.
#' @return  Returns an object of class "virf".
#' @references Hafner CM, Herwartz H (2006). Volatility impulse responses for multivariate GARCH models:  An exchange rate illustration. Journal of International Money and Finance,25,719–740.
#' @examples
#' \donttest{
#'
#' data(StocksBonds)
#' obj_spec <- bekk_spec()
#' x1 <- bekk_fit(obj_spec, StocksBonds, QML_t_ratios = FALSE, max_iter = 50, crit = 1e-9)
#'
#' # 250 day ahead VIRFs and 90% CI for a Shock in the 1% quantile  of Bonds (i.e. series=2)
#' # shock is supposed to occur at day 500
#' x2 <- virf(x1, time = 500, q = 0.01, index_series=2, n.ahead = 500, ci = 0.90)
#' plot(x2)
#' }
#' @import xts
#' @import stats
#' @import numDeriv
#' @export

virf <- function(x ,time = 1, q = 0.05, index_series = 1, n.ahead = 10, ci = 0.9, time_shock = FALSE){

  if (!inherits(x, 'bekkFit')) {
    stop('Please provide and object of class "bekkFit" for x')
  }

  if (x$spec$model$asymmetric==T) {
    stop('VIRFs are implemented only for symmetric BEKK models.')
  }


  if(!( n.ahead%%1==0) || n.ahead < 1){
    stop('Please provide a posive integer for periods')
  }

  if(!(index_series%%1==0) || index_series < 1){
    stop('Please provide a posive integer for index_series')
  }
  if(index_series > ncol(x$data)){
    stop('Total number of indices in the data is lower than index_series')
  }
  if(!is.numeric(time)){
    if( !is.numeric(x$data[time]) || nrow(x$data[time])==0){
  stop('Provided date object is not included in data')
    }
  }else{
  if((time%%1!=0 || time < 1) ){
    stop('Please provide a posive integer or a date object for time')
  }else if(!(time%%1!=0 || time < 1) && time > nrow(x$data)){
    stop('Total number of observations is exeded by time')
  }
  }

  if(!is.numeric(q) || q < 0 || q > 1 || length(q)>1 || length(q) == 0){
    stop('Please provide a number in the interval (0,1) for q.')

  }
  UseMethod('virf')

}

#' @export
virf.bekk <- function(x, time = 1, q = 0.05, index_series=1, n.ahead = 10, ci = 0.9, time_shock = FALSE) {

  N <- ncol(x$data)
  data <- x$data
  H <- matrix(x$H_t[time,],N,N)
  #get quantiles of returns
  residuals = x$e_t
  if(!time_shock ){
  shocks = matrix(0, nrow = 1, ncol = N)

  shocks[index_series] = sapply(q,FUN=quantile,x=as.matrix(residuals[,index_series]))
  for(i in 1: N){
    if(i==index_series){
      shocks[index_series] = sapply(q,FUN=quantile,x=as.matrix(residuals[,index_series]))
    }else{
      shocks[i] = sapply(0.5,FUN=quantile,x=as.matrix(residuals[,i])) *0

    }
  }
  }else{
    shocks = matrix(x$e_t[time,],nrow = 1, ncol = N)
  }

  VIRF = virf_bekk(H, x$theta, matrix(shocks, ncol=N, nrow = 1), n.ahead)
  #dupl <- duplication_mat(N)
  #elim <- elimination_mat(N)

  score_final = score_bekk(x$theta, x$data)
  score_outer = t(score_final) %*% score_final
  # s1 = eigen_value_decomposition(s1_temp)
  hesse_final = solve(hesse_bekk(x$theta, x$data))
  #s1_temp = solve(hesse_final)
  if(x$QML_t_ratios==TRUE){
    Sigma_temp=hesse_final%*%score_outer%*%hesse_final
  }else{
    Sigma_temp=solve(score_outer)
  }

  s1_temp = function(th){
    virf_bekk(H, th, matrix(shocks, ncol=N, nrow = 1), n.ahead)
  }

  th<-x$theta
  d_virf = jacobian(s1_temp,th)
  s1_temp=d_virf%*%Sigma_temp%*%t(d_virf)


#   s1 = s1_temp*0
#   counter = 1
#   while(counter < nrow(s1)){
#     s1[counter:(counter+n.ahead-1),counter:(counter+n.ahead-1)]=s1_temp[counter:(counter+n.ahead-1),counter:(counter+n.ahead-1)]
#   counter = counter + n.ahead
# }

  s1 = sqrt(abs(diag(s1_temp))) * qnorm(ci)
  #return(s1)
  #print(det(d_virf%*%hesse_final%*%t(d_virf)))
  VIRF_lower = VIRF  - matrix(s1, nrow = n.ahead, ncol = N*(N+1)/2)

  VIRF_upper = VIRF + matrix(s1, nrow = n.ahead, ncol = N*(N+1)/2)

  # for (i in 1:nrow(VIRF)) {
  #   tm <- matrix((dupl%*%VIRF[i,]), N, N, byrow = T)
  #   tm2 <- sqrt(solve(diag(abs(diag(tm)))))%*%tm%*%sqrt(solve(diag(abs(diag(tm)))))
  #   diag(tm2) <- sqrt(abs(diag(tm)))%*%solve(diag(abs(diag(tm))))%*%diag(diag(tm))
  #   VIRF[i,] <- elim%*%c(tm2)
  # }




  VIRF <- as.data.frame(VIRF)
  VIRF_lower <- as.data.frame(VIRF_lower)
  VIRF_upper <- as.data.frame(VIRF_upper)
  for(i in 1:ncol(VIRF)){
    colnames(VIRF)[i] <- paste("VIRF for", colnames(x$sigma_t)[i], sep=" ")
         }

  colnames(VIRF) <- gsub("Conditional","conditional",  colnames(VIRF))
  colnames(VIRF) <- gsub("correlation","covariance",  colnames(VIRF))
  colnames(VIRF) <- gsub("standard deviation","variance",  colnames(VIRF))

  result <- list(VIRF=VIRF,
                 VIRF_upper=VIRF_upper,
                 VIRF_lower=VIRF_lower,
                 N=N,
                 time=time,
                 q=q,
                 index_series=index_series,
                 x=x)
  class(result) <- c('virf','bekkFit', 'bekk')
  return(result)
}
#' @export
virf.dbekk <- function(x, time = 1, q = 0.05, index_series=1, n.ahead = 10, ci = 0.9, time_shock = FALSE) {

  N <- ncol(x$data)
  data <- x$data
  H <- matrix(x$H_t[time,],N,N)
  #get quantiles of returns
  residuals = x$e_t
  shocks = matrix(0, nrow = 1, ncol = N)
  if(!time_shock ){
  shocks[index_series] = sapply(q,FUN=quantile,x=as.matrix(residuals[,index_series]))
  for(i in 1: N){
    if(i==index_series){
      shocks[index_series] = sapply(q,FUN=quantile,x=as.matrix(residuals[,index_series]))
    }else{
      shocks[i] = sapply(0.5,FUN=quantile,x=as.matrix(residuals[,i])) * 0

    }
  }
  }else{
    shocks = matrix(x$e_t[time,],nrow = 1, ncol = N)
  }
  VIRF = virf_dbekk(H, x$theta, matrix(shocks, ncol=N, nrow = 1), n.ahead)

  hesse_final = solve(hesse_dbekk(x$theta, x$data))
  score_final = score_dbekk(x$theta, x$data)
  score_outer = t(score_final) %*% score_final
  if(x$QML_t_ratios==TRUE){
    Sigma_temp=hesse_final%*%score_outer%*%hesse_final
  }else{
    Sigma_temp=solve(score_outer)
  }

  s1_temp = function(th){
    virf_dbekk(H, th, matrix(shocks, ncol=N, nrow = 1), n.ahead)
  }

  th<-x$theta
  d_virf = jacobian(s1_temp,th)
  s1_temp=d_virf%*%Sigma_temp%*%t(d_virf)
  #   s1 = s1_temp*0
  #   counter = 1
  #   while(counter < nrow(s1)){
  #     s1[counter:(counter+n.ahead-1),counter:(counter+n.ahead-1)]=s1_temp[counter:(counter+n.ahead-1),counter:(counter+n.ahead-1)]
  #   counter = counter + n.ahead
  # }

  s1 = sqrt(diag(s1_temp)) * qnorm(ci)
  #return(s1)
  #print(det(d_virf%*%hesse_final%*%t(d_virf)))
  VIRF_lower = VIRF  - matrix(s1, nrow = n.ahead, ncol = N*(N+1)/2)

  VIRF_upper = VIRF + matrix(s1, nrow = n.ahead, ncol = N*(N+1)/2)

  # for (i in 1:nrow(VIRF)) {
  #   tm <- matrix((dupl%*%VIRF[i,]), N, N, byrow = T)
  #   tm2 <- sqrt(solve(diag(abs(diag(tm)))))%*%tm%*%sqrt(solve(diag(abs(diag(tm)))))
  #   diag(tm2) <- sqrt(abs(diag(tm)))%*%solve(diag(abs(diag(tm))))%*%diag(diag(tm))
  #   VIRF[i,] <- elim%*%c(tm2)
  # }




  VIRF <- as.data.frame(VIRF)
  VIRF_lower <- as.data.frame(VIRF_lower)
  VIRF_upper <- as.data.frame(VIRF_upper)
  for(i in 1:ncol(VIRF)){
    colnames(VIRF)[i] <- paste("VIRF for", colnames(x$sigma_t)[i], sep=" ")

  }
  colnames(VIRF) <- gsub("Conditional","conditional",  colnames(VIRF))
  colnames(VIRF) <- gsub("correlation","covariance",  colnames(VIRF))
  colnames(VIRF) <- gsub("standard deviation","variance",  colnames(VIRF))



  result <- list(VIRF=VIRF,
                 VIRF_upper=VIRF_upper,
                 VIRF_lower=VIRF_lower,
                 N=N,
                 time=time,
                 q=q,
                 index_series=index_series,
                 x=x)
  class(result) <- c('virf','bekkFit', 'dbekk')
  return(result)
}
#' @export
virf.sbekk <- function(x, time = 1, q = 0.05, index_series=1, n.ahead = 10, ci = 0.9, time_shock = FALSE) {

  N <- ncol(x$data)
  data <- x$data
  H <- matrix(x$H_t[time,],N,N)
  #get quantiles of returns
  residuals = x$e_t
  shocks = matrix(0, nrow = 1, ncol = N)
  if(!time_shock ){
  shocks[index_series] = sapply(q,FUN=quantile,x=as.matrix(residuals[,index_series]))
  for(i in 1: N){
    if(i==index_series){
      shocks[index_series] = sapply(q,FUN=quantile,x=as.matrix(residuals[,index_series]))
    }else{
      shocks[i] = sapply(0.5,FUN=quantile,x=as.matrix(residuals[,i])) * 0

    }
  }
  }else{
    shocks = matrix(x$e_t[time,],nrow = 1, ncol = N)
  }

  VIRF = virf_sbekk(H, x$theta, matrix(shocks, ncol=N, nrow = 1), n.ahead)
  #dupl <- duplication_mat(N)
  #elim <- elimination_mat(N)

  # score_final = score_bekk(x$theta, x$data)
  # s1_temp = solve(t(score_final) %*% score_final)
  # s1 = eigen_value_decomposition(s1_temp)
  #hesse_final = solve(hesse_sbekk(x$theta, x$data))
  #s1_temp = solve(hesse_final)

  hesse_final = solve(hesse_sbekk(x$theta, x$data))
  score_final = score_sbekk(x$theta, x$data)
  score_outer = t(score_final) %*% score_final
  if(x$QML_t_ratios==TRUE){
    Sigma_temp=hesse_final%*%score_outer%*%hesse_final
  }else{
    Sigma_temp=solve(score_outer)
  }

  s1_temp = function(th){
    virf_dbekk(H, th, matrix(shocks, ncol=N, nrow = 1), n.ahead)
  }

  s1_temp = function(th){
    virf_sbekk(H, th, matrix(shocks, ncol=N, nrow = 1), n.ahead)
  }

  th<-x$theta
  d_virf = jacobian(s1_temp,th)
  s1_temp=d_virf%*%Sigma_temp%*%t(d_virf)
  #   s1 = s1_temp*0
  #   counter = 1
  #   while(counter < nrow(s1)){
  #     s1[counter:(counter+n.ahead-1),counter:(counter+n.ahead-1)]=s1_temp[counter:(counter+n.ahead-1),counter:(counter+n.ahead-1)]
  #   counter = counter + n.ahead
  # }

  s1 = sqrt(diag(s1_temp)) * qnorm(ci)  #return(s1)
  #print(det(d_virf%*%hesse_final%*%t(d_virf)))
  VIRF_lower = VIRF  - matrix(s1, nrow = n.ahead, ncol = N*(N+1)/2)

  VIRF_upper = VIRF + matrix(s1, nrow = n.ahead, ncol = N*(N+1)/2)

  # for (i in 1:nrow(VIRF)) {
  #   tm <- matrix((dupl%*%VIRF[i,]), N, N, byrow = T)
  #   tm2 <- sqrt(solve(diag(abs(diag(tm)))))%*%tm%*%sqrt(solve(diag(abs(diag(tm)))))
  #   diag(tm2) <- sqrt(abs(diag(tm)))%*%solve(diag(abs(diag(tm))))%*%diag(diag(tm))
  #   VIRF[i,] <- elim%*%c(tm2)
  # }




  VIRF <- as.data.frame(VIRF)
  VIRF_lower <- as.data.frame(VIRF_lower)
  VIRF_upper <- as.data.frame(VIRF_upper)
  for(i in 1:ncol(VIRF)){
    colnames(VIRF)[i] <- paste("VIRF for", colnames(x$sigma_t)[i], sep=" ")

  }

  colnames(VIRF) <- gsub("Conditional","conditional",  colnames(VIRF))
  colnames(VIRF) <- gsub("correlation","covariance",  colnames(VIRF))
  colnames(VIRF) <- gsub("standard deviation","variance",  colnames(VIRF))


  result <- list(VIRF=VIRF,
                 VIRF_upper=VIRF_upper,
                 VIRF_lower=VIRF_lower,
                 N=N,
                 time=time,
                 q=q,
                 index_series=index_series,
                 x=x)
  class(result) <- c('virf','bekkFit', 'sbekk')
  return(result)
}
