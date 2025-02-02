#' @title carbonstock
#' @description reads carbon stocks out of a MAgPIE gdx file
#' 
#' @export
#'
#' @param gdx GDX file
#' @param file a file name the output should be written to using write.magpie
#' @param level Level of regional aggregation; "cell", "reg" (regional), "glo" (global), "regglo" (regional and global) or any secdforest aggregation level defined in superAggregate
#' @param sum_cpool sum over carbon pool dimension (default = TRUE)
#' @param sum_land sum over land type dimension (default = TRUE)
#' @param cc account for climate change impacts on carbon stocks (default = TRUE). FALSE reflects only carbon stock changes due to land management.
#' @param cc_year year for fixing carbon density if cc=FALSE (default = 1995)
#' @param regrowth TRUE (default) or FALSE. FALSE returns pure land-use change emissions. Works only in combination with CC=FALSE. 
#' @details carbon pools consist of vegetation carbon (vegc), litter carbon (litc) and soil carbon (soilc)
#' @return carbon stocks in MtC
#' @author Florian Humpenoeder
#' @importFrom gdx readGDX out
#' @importFrom magclass clean_magpie dimSums collapseNames setYears write.magpie
#' @importFrom luscale superAggregate
#' @examples
#' 
#'   \dontrun{
#'     x <- carbonstock(gdx)
#'   }
#' 

carbonstock <- function(gdx, file=NULL, level="cell", sum_cpool=TRUE, sum_land=TRUE, cc=TRUE, cc_year=1995, regrowth=TRUE){
  
  #read in carbon stocks
  a <- readGDX(gdx,"ov_carbon_stock",select=list(type="level"),react="silent")
  names(dimnames(a))[1] <- "j"
  
  #recalculate carbon stocks without CC impacts if cc=FALSE
  #if the MAgPIE run was performed with static input cc=TRUE/FALSE should return identical results
  if(!cc) {
    
    weighted_mean <- function(x,weight,map) {
      #carbon density * area
      a <- clean_magpie(x[map]) * clean_magpie(weight[map])
      #aggregate age-classes
      a <- dimSums(a,dim=c(3.1))
      weight <- dimSums(clean_magpie(weight[map]),dim=c(3.1))
      #calculate new carbon density
      a <- a/weight
      a[is.na(a)] <- 0
      return(a)
    }
    
    #use same structure
    b <- a
    b[,,] <- 0
    
    #read in needed parameters and variables
    t <- readGDX(gdx,"t")
    
    ov_land <- readGDX(gdx,"ov_land",select = list(type="level"))
    names(dimnames(ov_land))[1] <- "j"
    
    #read in carbon density and fix on cc_year
    fm_carbon_density <- readGDX(gdx,"fm_carbon_density")[,t,]
    names(dimnames(fm_carbon_density))[2] <- "t"
    fm_carbon_density[,,] <- setYears(fm_carbon_density[,cc_year,],NULL)
    
    #read in ac-specifc carbon density and fix on cc_year
    pm_carbon_density_ac <- readGDX(gdx,"pm_carbon_density_ac")
    pm_carbon_density_ac[,,] <- setYears(pm_carbon_density_ac[,cc_year,],NULL)
    som_on <- !is.element("soilc", getNames(pm_carbon_density_ac,dim=2))
    
    if(som_on){
      
      ag_pools <- c("litc", "vegc")
      
      #test dynamic vs. static
      if(dym_som <- !is.null(readGDX(gdx, "ov59_som_pool", react="silent"))){
        
        pools59   <- readGDX(gdx, "pools59", types="sets", react="silent")
        
        cshare    <- cshare(gdx, level="cell", noncrop_aggr=FALSE, reference="actual")[,,"total",invert=TRUE]
        cshare[is.na(cshare)]     <- 1
        
        b[,,"crop"][,,ag_pools]         <- fm_carbon_density[,,"crop"][,,ag_pools]       * ov_land[,,"crop"]  
        b[,,"past"][,,ag_pools]         <- fm_carbon_density[,,"past"][,,ag_pools]       * ov_land[,,"past"]
        b[,,"urban"]                    <- fm_carbon_density[,,"urban"]                  * ov_land[,,"urban"]
        b[,,"primforest"][,,ag_pools]   <- fm_carbon_density[,,"primforest"][,,ag_pools] * ov_land[,,"primforest"]
        
        b[,,pools59][,,"soilc"]         <- fm_carbon_density[,,pools59][,,"soilc"] * cshare * ov_land[,,pools59]  
        
      } else { 
        
        i59_topsoilc_density     <- readGDX(gdx, "i59_topsoilc_density")[,t,]
        i59_topsoilc_density[,,] <- setYears(i59_topsoilc_density[,cc_year,], NULL)
        i59_subsoilc_density     <- readGDX(gdx, "i59_subsoilc_density")[,t,]
        i59_subsoilc_density[,,] <- setYears(i59_subsoilc_density[,cc_year,], NULL)
        
        #cropland, pasture, urban land and primforest is simple
        b[,,"crop"][,,ag_pools]         <- fm_carbon_density[,,"crop"][,,ag_pools] * ov_land[,,"crop"] 
        b[,,"crop"][,,"soilc"]          <- (i59_topsoilc_density + i59_subsoilc_density)   * ov_land[,,"crop"]
        b[,,"past"]                     <- fm_carbon_density[,,"past"]                     * ov_land[,,"past"]
        b[,,"urban"]                    <- fm_carbon_density[,,"urban"]                    * ov_land[,,"urban"]
        b[,,"primforest"]               <- fm_carbon_density[,,"primforest"]               * ov_land[,,"primforest"]
        b[,,"secdforest"][,,"soilc"]    <- fm_carbon_density[,,"secdforest"][,,"soilc"]    * ov_land[,,"secdforest"]
        b[,,"forestry"][,,"soilc"]      <- fm_carbon_density[,,"forestry"][,,"soilc"]      * ov_land[,,"forestry"]
        b[,,"other"][,,"soilc"]         <- fm_carbon_density[,,"other"][,,"soilc"]         * ov_land[,,"other"]
      }
      
    } else {
      
      #cropland, pasture, urban land and primforest is simple
      b[,,"crop"]                  <- fm_carbon_density[,,"crop"]*ov_land[,,"crop"] 
      b[,,"past"]                  <- fm_carbon_density[,,"past"]*ov_land[,,"past"]
      b[,,"urban"]                 <- fm_carbon_density[,,"urban"]*ov_land[,,"urban"]
      b[,,"primforest"]            <- fm_carbon_density[,,"primforest"]*ov_land[,,"primforest"]
    }
    
    
    #forestry land
    ####################
    p32_land <- readGDX(gdx,"p32_land","p32_land_fore",react = "quiet")
    if(is.null(p32_land)) {
      
      b[,,"forestry"] <- fm_carbon_density[,,"forestry"]*ov_land[,,"forestry"]
      
    } else { 
      
      names(dimnames(p32_land))[1] <- "j"
      p32_carbon_density_ac <- readGDX(gdx,"p32_carbon_density_ac",react = "quiet")
      
      if(!is.null(p32_carbon_density_ac)) {
        
        if(!regrowth) {
          ac <- getNames(p32_land,dim = "ac")
          p32_land[,,ac[1]] <- dimSums(p32_land[,,ac[61],invert=T],dim=3)
          p32_land[,,ac[2:60]] <- 0
        }
        if(som_on){
          b[,,"forestry"][,,ag_pools]  <- dimSums(p32_carbon_density_ac*p32_land,dim=c(3.1,3.2))
        } else {
          b[,,"forestry"]              <- dimSums(p32_carbon_density_ac*p32_land,dim=c(3.1,3.2))
        }
        
        
      } else {
        
        if(dim(p32_land)[3] == 122) p32_land <- collapseNames(p32_land[,,"after"])
        if(!regrowth) {
          ac <- getNames(p32_land,dim = "ac")
          p32_land[,,ac[1]] <- dimSums(p32_land[,,ac[61],invert=T],dim=3)
          p32_land[,,ac[2:60]] <- 0
        }
        if(som_on){
          b[,,"forestry"][,,ag_pools] <- dimSums(pm_carbon_density_ac*p32_land,dim=3.1)
        } else {
          b[,,"forestry"]             <- dimSums(pm_carbon_density_ac*p32_land,dim=3.1)
        }
      }
    }
    ####################
    
    #secdforest 
    ####################
    p35_secdforest <- readGDX(gdx,"p35_secdforest",react = "quiet")
    if(is.null(p35_secdforest)) {
      b[,,"secdforest"] <- fm_carbon_density[,,"secdforest"]*ov_land[,,"secdforest"]
    } else {
      names(dimnames(p35_secdforest))[1] <- "j"
      if(dim(p35_secdforest)[3] == 122) p35_secdforest <- collapseNames(p35_secdforest[,,"after"])
      if(!regrowth) {
        ac <- getNames(p35_secdforest,dim = "ac")
        p35_secdforest[,,ac[1]] <- dimSums(p35_secdforest[,,ac[61],invert=T],dim=3)
        p35_secdforest[,,ac[2:60]] <- 0
      }
      if(som_on){
        b[,,"secdforest"][,,ag_pools] <- dimSums(pm_carbon_density_ac*p35_secdforest,dim=3.1)
      } else {
        b[,,"secdforest"]                     <- dimSums(pm_carbon_density_ac*p35_secdforest,dim=3.1)
      }
    }
    ####################
    
    #other land 
    ####################
    p35_other <- readGDX(gdx,"p35_other",react = "quiet")
    if(is.null(p35_other)) {
      b[,,"other"] <- fm_carbon_density[,,"other"]*ov_land[,,"other"]
    } else {
      names(dimnames(p35_other))[1] <- "j"
      if(dim(p35_other)[3] == 122) p35_other <- collapseNames(p35_other[,,"after"])
      if(!regrowth) {
        ac <- getNames(p35_other,dim = "ac")
        p35_other[,,ac[1]] <- dimSums(p35_other[,,ac[61],invert=T],dim=3)
        p35_other[,,ac[2:60]] <- 0
      }
      if(som_on){
        b[,,"other"][,,ag_pools] <- dimSums(pm_carbon_density_ac*p35_other,dim=3.1)
      } else {
        b[,,"other"]                     <- dimSums(pm_carbon_density_ac*p35_other,dim=3.1)
      }
    }
    ####################
    

    #replace carbon stock
    a <- b
  }
  
  #rounding
  a <- round(a,digits = 3)
  
  #sum over land pools
  if (sum_land) a <- dimSums(a,dim="land")
  
  #sum over carbon pools
  if (sum_cpool) a <- dimSums(a,dim="c_pools")
  
  #aggregate over regions
  if (level != "cell") a <- superAggregate(a, aggr_type = "sum", level = level,na.rm = FALSE)
  
  out(a,file)
}
