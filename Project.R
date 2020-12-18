---
  title: "Markov Chain Analysis of MLB Pitching"
author: "Carter Hall"
date: "December 16th, 2020"
output:
  pdf_document: default
html_notebook: default
html_document:
  df_print: paged
---

knitr::opts_chunk$set(echo = TRUE, message = FALSE, warning = FALSE)
 
library(readr)
library(devtools)
library(baseballr)
library(dplyr)
library(ggplot2)
library(msm)
library(leaflet)
library(gt)
library(webshot)
library(ricomisc)
library(pitchRx)
 

pData <- scrape_statcast_savant_pitcher_all("2020-07-23", "2020-08-01")
pData <- rbind(pData, scrape_statcast_savant_pitcher_all("2020-08-01", "2020-08-10"))
pData <- rbind(pData, scrape_statcast_savant_pitcher_all("2020-08-10", "2020-08-16"))
pData <- rbind(pData, scrape_statcast_savant_pitcher_all("2020-08-17", "2020-08-24"))
pData <- rbind(pData, scrape_statcast_savant_pitcher_all("2020-08-24", "2020-09-02"))
pData <- rbind(pData, scrape_statcast_savant_pitcher_all("2020-09-02", "2020-09-09"))
pData <- rbind(pData, scrape_statcast_savant_pitcher_all("2020-09-10", "2020-09-17"))
pData <- rbind(pData, scrape_statcast_savant_pitcher_all("2020-09-24", "2020-10-01"))
pData <- rbind(pData, scrape_statcast_savant_pitcher_all("2020-10-01", "2020-10-09"))
pData <- rbind(pData, scrape_statcast_savant_pitcher_all("2020-10-10", "2020-10-20"))
pData <- rbind(pData, scrape_statcast_savant_pitcher_all("2020-10-21", "2020-10-27"))
 
pData <- pData[dim(pData)[1]:1,]
for (i in 1:nrow(pData)) {
  if (pData$events[i] == "null") {
    pData$events[i] = NA
  }
}
rm(i)
write.csv(pData, "2020season_pitchers.csv")
 
pData <- read_csv("2020season_pitchers.csv")
 
selectPitcher <- function(dataset, name) {
  return (dataset %>% filter(dataset$player_name == name))
}
 

   
# Note: I sourced the bodies of these functions from a useful Stack Overflow post:
# https://stackoverflow.com/questions/63944953/how-to-conditionally-format-a-cell-in-a-gt-table-based-on-the-value-of-the-cel 

fill_column <- function(gtobj, dataframe, column){
  heat_palette <- leaflet::colorNumeric(palette = c("#EAF6FA", "#E5F9FF", "#72DCFF"),
                                        domain = dataframe$value)
  
  ht_values <- heat_palette(dataframe %>% pull(sym(column)))
  
  for(i in seq_along(dataframe %>% pull(sym(column)))) {
    
    gtobj <- gtobj %>%
      tab_style(style = cell_fill(color = ht_values[i]),
                locations = cells_body(columns = column, rows = i))
  }
  return(gtobj)
}

color_table <- function(gtobj, dataframe) {
  for (k in 1:length(colnames(dataframe))) {
    gtobj <- fill_column(gtobj, dataframe, colnames(dataframe)[k])
  }
  return(gtobj)
}
 

   
idCreator <- function(dataset) {
  dataset$gameID <- paste(dataset$game_date, dataset$away_team, dataset$home_team, sep = " ")
  
  dataset$abID = 1
  for (i in 2:nrow(dataset)) {
    if (!(is.na(dataset$events[i - 1]))) {
      dataset$abID[i:nrow(dataset)] = dataset$abID[i:nrow(dataset)] + 1 
    }
  }
  dataset$orderID = (dataset$abID %% 9) + 1
  
  return(dataset)
}
 

   
typeResMatrixStates <- function(dataset) {
  
  typeres = c()
  
  for (i in 1:nrow(dataset)) {
    
    res = ""
    
    if (dataset$description[i] %in% c("ball", "blocked_ball")) {
      res = "B"
    }
    else if (dataset$description[i] %in% c("called_strike")) {
      res = "CS"
    }
    else if (dataset$description[i] %in% c("swinging_strike", "swinging_strike_blocked", 
                                           "missed_bunt") | 
             (dataset$description[i] %in% c("foul", "foul_tip", "foul_bunt")) |
             (dataset$description[i] %in% c("hit_into_play_no_out", "hit_into_play",
                                            "hit_into_play_score"))) {
      res = "SW"
    }
    
    typeres[i] = paste(dataset$pitch_type[i], res, sep = ",")
  }
  dataset$typeres = typeres
  
  return(dataset)
}


 

   
swingMatrixStates <- function(dataset, hcThreshold, hcEpsilon) {
  
  contact = c()
  thres = hcThreshold
  ep = hcEpsilon
  
  for (i in 1:nrow(dataset)) {
    
    type = ""
    
    if (!(is.na(dataset$launch_speed[i]))) {
      if (dataset$launch_speed[i] >= (thres - ep)) {
        type = "C+"
      }
      
      else if (dataset$launch_speed[i] < (hcThreshold - hcEpsilon) |
               dataset$description[i] %in% c("foul", "foul_bunt", "foul_tip")) {
        type = "C-"
      }
    }
    
    else if (dataset$description[i] %in% c("swinging_strike", "swinging_strike_blocked", 
                                           "missed_bunt")) {
      type = "SWM"
    }
    
    contact[i] = paste(dataset$pitch_type[i], type, sep = ",")
  }
  
  dataset$swingContact = contact
  return(dataset)
}
 

   
saveMatrix <- function(matrix, filename) {
  gtsave(matrix, filename)
  print(paste("Table saved to", filename))
  rstudio_viewer(filename)
}
 

   
markovTransitionMatrix <- function(dataset, statesVar, dividerVar, precision, 
                                   titleString, subtitleString, captionString, 
                                   filenameToSave) {
  countMatrix = statetable.msm(statesVar, dividerVar, dataset)
  transMatrix = round(t(t(countMatrix) / rep(rowSums(countMatrix), each=ncol(countMatrix))),precision)
  
  df = data.frame()
  for (j in 1:dim(countMatrix)[1]) {
    df <- rbind(df, data.frame(t(as.vector(transMatrix[j,]))))
  }
  colnames(df) <- names(transMatrix[j,])
  rownames(df) <- names(transMatrix[,j])
  
  gtobj <- gt(df, rownames_to_stub = TRUE) %>%
    tab_header(
      title = ifelse(is.na(titleString), " ", titleString),
      subtitle = ifelse(is.na(subtitleString), " ", subtitleString)
    ) %>%
    tab_source_note(ifelse(is.na(captionString), " ", captionString))
  
  gtobj <- color_table(gtobj, df)
  saveMatrix(gtobj, filenameToSave)
  
  return(list(table = gtobj, file = filenameToSave, matrix = transMatrix))
}
 

kershawData <- selectPitcher(pData, "Clayton Kershaw")
 
kershawData <- idCreator(kershawData)
 
gg1 <- ggplot(data = data.frame(type = kershawData$pitch_type),
              mapping = aes(x = type)) + geom_bar(stat = "count") + 
  geom_text(stat='count', aes(label=..count..), vjust= 0, color = "red") +
  labs(
    title = "Histogram of Pitches Thrown, by Type",
    subtitle = "For Clayton Kershaw in 2020 MLB Season"
  ) +
  theme(plot.title = element_text(hjust = 0.5),
        plot.subtitle = element_text(hjust = 0.5)) 

ggsave("img1.png", gg1)

# There is a large skew with respect to the number of CH used, so I will 
# remove that at-bat from the analysis. The probabilities would be VERY small.
absToRemove = c()
index = 1
for (j in 1:nrow(kershawData)) {
  if (kershawData$pitch_type[j] == "CH") {
    absToRemove[index] = kershawData$abID[j]
    index = index + 1
  }
}
rm(j)
removeThese <- subset(kershawData, kershawData$abID %in% absToRemove)
kershawData <- kershawData[!kershawData$abID %in% removeThese$abID,]
rm(removeThese)
 
m1 <- markovTransitionMatrix(kershawData, kershawData$pitch_type, kershawData$abID, 3, 
                             "Transition Matrix for Pitch Types for Clayton Kershaw in 2020 MLB Season", 
                             "To Read: \"From\" [Row Entry] \"To\" [Column Entry] has Prob. [Cell]",
                             "CU: Cutter, FF: Four-Seam Fastball, SL: Slider",
                             "ck_MarkovTypeMatrix.html"
)
m1$table
 
# First! Remove the one instance of HBP -- not important for swing/not-swing -- 
# there's the obvious reason they didn't choose to swing... they attempted to dodge!

kershawData <- kershawData[!kershawData$description %in% c("hit_by_pitch"),]
kershawData <- typeResMatrixStates(kershawData)
 

   
m2 <- markovTransitionMatrix(kershawData, kershawData$typeres, kershawData$abID, 3, 
                             "Transition Matrix for Pitch Type-Results for Clayton 
                             Kershaw in 2020 MLB Season",
                             "To Read: \"From\" [Row Entry] \"To\" [Column Entry] has Prob. 
                             [Cell]",
                             "CU: Cutter, FF: Four-Seam Fastball, SL: Slider || 
                             B: Ball, CS: Called Strike (no swing), SW: Swing (Includes Hit,
                             Foul, Swing and Miss (SWM)",
                             "ck_MarkovTypeResMatrix.html")
m2$table
 
kershawSwings <- subset(kershawData, grepl("SW", kershawData$typeres) == TRUE)
kershawSwings <- swingMatrixStates(kershawSwings, 90.0, 1.0)

# Removing any cases of missed launch speed recording
kershawSwings <- (kershawSwings %>% filter(nchar(kershawSwings$swingContact) != 3))

m3 <- markovTransitionMatrix(kershawSwings, kershawSwings$swingContact, kershawSwings$abID, 
                             3, 
                             "Transition Matrix for Pitch Type-Swing Contact Results for 
                             Clayton Kershaw in 2020 MLB Season", 
                             "To Read: \"From\" [Row Entry] \"To\" [Column Entry] has Prob. 
                             [Cell]",
                             "CU: Cutter, FF: Four-Seam Fastball, SL: Slider || 
                             C-: Soft Contact (Includes Foul Balls), 
                             C+: Hard Contact (~90+ mph Exit Velo),
                             SWM: Swing and Miss",
                             "ck_MarkovTypeSwingMatrix.html"
)
m3$table
 
probThreeEvents <- function(values) {
  
  probs = c()
  
  for (i in 1:dim(values)[2]) {
    probs[i] = (values[1,i] + values[2,i] + values[3,i] 
                - (values[1,i] * values[2,i]) 
                - (values[1,i] * values[3,i])
                - (values[2,i] * values[3,i]) 
                + (values[1,i] * values[2,i] * values[3,i]))
  }
  
  return(probs)
}

oldTransMatrix <- unname(m2$matrix)
cuProb <- oldTransMatrix[1:3,]
ffProb <- oldTransMatrix[4:6,]
slProb <- oldTransMatrix[7:9,]

# This step worries me...
newCUProb <- round(probThreeEvents(cuProb) / sum(probThreeEvents(cuProb)), 3)
newFFProb <- round(probThreeEvents(ffProb) / sum(probThreeEvents(ffProb)), 3)
newSLProb <- round(probThreeEvents(slProb) / sum(probThreeEvents(slProb)), 3)

newTransMatrix = matrix(NA, 3, 9)
newTransMatrix[1,] <- newCUProb
newTransMatrix[2,] <- newFFProb
newTransMatrix[3,] <- newSLProb
newTransMatrix_df <- data.frame(newTransMatrix, 
                                row.names = c("CU", "FF", "SL"))
colnames(newTransMatrix_df) <- sort(unique(kershawData$typeres))
gt1 <- gt(newTransMatrix_df, rownames_to_stub = TRUE) %>%
  tab_header(
    title = "Transition Matrix for Prev. Pitch to Next Pitch Type-Result for
      Clayton Kershaw in 2020 MLB Season",
    subtitle = "To Read: \"From\" [Row Entry] \"To\" [Column Entry] has Prob. 
                             [Cell]" 
  ) %>%
  tab_source_note("CU: Cutter, FF: Four-Seam Fastball, SL: Slider || 
                             B: Ball, CS: Called Strike (no swing), SW: Swing (Includes Hit,
                             Foul, Swing and Miss (SWM) || Rounding may make some rows have sums nonequal to 1 (i.e., 1.001 or 0.999).")
gt1 <- color_table(gt1, newTransMatrix_df)
gt1
saveMatrix(gt1, "ck_markovMatrixPTRows.html")
 

top_edge <- 3.5
bot_edge <- 1.5
left_edge <- -0.85
right_edge <- 0.85
sz <- data.frame(
  x=c(left_edge, left_edge, right_edge, right_edge, left_edge),
  y=c(bot_edge, top_edge, top_edge, bot_edge, bot_edge))
 

gg2 <- ggplot(data.frame(px = kershawData$plate_x, pz = kershawData$plate_z, 
                         type = kershawData$pitch_type, tr = kershawData$typeres), 
              aes(x = px, color = tr)) + geom_point(aes(y = pz)) +
  geom_path(aes(x,y),data = sz,lwd=1,col="black") +
  xlim(-2, 2) + ylim(-0.5, 5) +
  facet_wrap(~type)

ggsave("img6.png", gg2)
gg2
 

   
kershawSwings$contactOrMiss = c()

for (i in 1:nrow(kershawSwings)) {
  kershawSwings$contactOrMiss[i] = ifelse(grepl("SWM", kershawSwings$swingContact[i]), "Miss", "Contact")
}
 
gg3 <- ggplot(data.frame(px = kershawSwings$plate_x, pz = kershawSwings$plate_z, 
                         type = kershawSwings$pitch_type, cm = kershawSwings$contactOrMiss), 
              aes(x = px, color = cm)) + geom_point(aes(y = pz)) +
  geom_path(aes(x,y),data = sz,lwd=1,col="black") +
  xlim(-2, 2) + ylim(-0.5, 5) +
  facet_wrap(~type) +
  labs(title = "Locational Graph of Contact/Swing-and-Miss, by Pitch Type",
       subtitle = "For Clayton Kershaw in the 2020 MLB Season")

ggsave("img7.png", gg3)
 

gg4 <- ggplot(data.frame(px = kershawSwings$plate_x, pz = kershawSwings$plate_z, 
                         type = kershawSwings$pitch_type, sc = kershawSwings$swingContact), 
              aes(x = px, color = sc)) + geom_point(aes(y = pz)) +
  geom_path(aes(x,y),data = sz,lwd=1,col="black") +
  xlim(-2, 2) + ylim(-0.5, 5) +
  facet_wrap(~type) + 
  labs(title = "Location of Swing-Contact Events, by Pitch Type",
       subtitle = "For Clayton Kershaw in the 2020 MLB Season")

ggsave("img8.png", gg4)

gg5 <- ggplot(data = data.frame(typeres = kershawData$typeres),
              mapping = aes(x = typeres)) + geom_bar(stat = "count") + 
  geom_text(stat='count', aes(label=..count..), vjust= 0, color = "red") +
  labs(
    title = "Barplot of Pitch Type-Results",
    subtitle = "For Clayton Kershaw in 2020 MLB Season"
  ) +
  theme(plot.title = element_text(hjust = 0.5),
        plot.subtitle = element_text(hjust = 0.5)) 

ggsave("img9.png", gg5)

gg6 <- ggplot(data = data.frame(sc = kershawSwings$swingContact),
              mapping = aes(x = sc)) + geom_bar(stat = "count") + 
  geom_text(stat='count', aes(label=..count..), vjust= 0, color = "red") +
  labs(
    title = "Barplot of Swing-Contact Events",
    subtitle = "For Clayton Kershaw in 2020 MLB Season"
  ) +
  theme(plot.title = element_text(hjust = 0.5),
        plot.subtitle = element_text(hjust = 0.5)) 

ggsave("img10.png", gg6)
 
