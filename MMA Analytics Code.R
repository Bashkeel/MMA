setwd("C:/Users/Bashk/Desktop/Python/Projects/MMA")

library(Rmisc)
library(vcd)
library(ggplot2)
library(tidyr)
library(albersusa)
library(ggmap)
library(rworldmap)
library(knitr)
library(data.table)
library(dplyr)

# Loading the data
fights <- read.csv("Data/Fights2.csv")
finishes <- read.csv("Data/Cat.csv")
fighters <- read.csv("Data/Fighters.csv")
loc <- read.csv("Data/Areas2.csv")

# Merge the fights & detailed finishes datasets
fights <- merge(fights, finishes, by = "method_d", all = TRUE)

# Color Scheme for Plots:
sunshine_over_glacier <- c("#004056", "#2C858D", "#74CEB7", "#C9FFD5", "#FFFFCB")


## Striking versus Grappling: How do fighters win in MMA?

finishes_df <- setDT(fights) %>% 
  na.omit() %>%
  dplyr::select(Category, round) %>% 
  count(Category, round, sort = T) %>%
  filter(Category != "Decision") %>%
  mutate(Round = round)

finishes_catalogue <- finishes_df %>% group_by(Category) %>% summarise(total = sum(n)) %>% arrange(desc(-total))
finishes_df$Category <- factor(finishes_df$Category, levels=as.vector(finishes_catalogue$Category))

ggplot(finishes_df, aes(x=Category, y=n, fill=Round)) +
  geom_bar(aes(fill=as.factor(Round)), stat='identity', position = position_stack(reverse = TRUE), col = 'black', width=0.85) + 
  coord_flip() + labs(x="Win Method", y="Count") + ggtitle("Method of Win") +
  scale_fill_manual(values = (sunshine_over_glacier)) + theme_minimal()

finishes_table <- dcast(finishes_df, Category~round, value.var = 'n', fill = 0)
finishes_table <- finishes_table[order(rowSums(finishes_table[,2:6]), decreasing = TRUE),]

kable(finishes_table, row.names = F, align='l')


## Fight Like a Girl: Do gender differences exist in how MMA fights are won?

finishes_by_gender <- setDT(fights) %>% 
  na.omit() %>%
  dplyr::select(Category, Gender) %>% 
  count(Category, Gender, sort = T) %>%
  group_by(Gender) %>% 
  mutate(Percentage = as.numeric(format(round(n/sum(n)*100,2), nsmall = 2))) %>%
  dcast(Gender~Category, value.var='Percentage', fill=0) %>%
  melt(id.vars = c('Gender'), variable.name = 'Category', value.name = 'Percentage') 

ggplot(finishes_by_gender, aes(x=reorder(Category, Percentage), y=Percentage, fill=Gender)) +
  geom_bar(position = "dodge", stat='identity', col='black', width=0.85) + coord_flip() +
  scale_fill_manual(values=c(sunshine_over_glacier[1], sunshine_over_glacier[4])) + 
  labs(x="Win Method", y="Percantage of Fights") + theme_minimal() +
  ggtitle("Differences in Finishes by Gender")

gendered_finish_catalogue <- finishes_by_gender %>%
  group_by(Category) %>% summarise(average = mean(Percentage)) %>%
  arrange(desc(average)) %>% dplyr::select(Category)

gendered_finishes_table <- dcast(finishes_by_gender, Gender~Category, value.var='Percentage', fill=0)
gendered_finishes_table <- gendered_finishes_table[,c("Gender", as.vector(gendered_finish_catalogue$Category))]
kable(gendered_finishes_table, row.names = F, align='l')


## Differences in decision wins by gender

decisions_by_gender <- setDT(fights) %>% 
  na.omit() %>%
  dplyr::select(Category, method_d, Gender) %>%
  filter(method_d %in% c("Unanimous", "Split", "Majority") & Category == "Decision") %>%
  count(method_d, Gender, sort = T) %>%
  group_by(Gender) %>% 
  mutate(Percentage = as.numeric(format(round(n/sum(n)*100,2), nsmall = 2))) %>%
  dcast(Gender~method_d, value.var='Percentage', fill=0) %>%
  melt(id.vars = c('Gender'), variable.name = 'Decision Method', value.name = 'Percentage')


ggplot(decisions_by_gender, aes(x=reorder(`Decision Method`, Percentage), y=Percentage, fill=Gender)) +
  geom_bar(position = "dodge", stat='identity', col='black', width=0.85) + coord_flip() +
  scale_fill_manual(values=c(sunshine_over_glacier[1], sunshine_over_glacier[4])) + 
  labs(x="Win Method", y="Percentage of Fights") + theme_minimal()

gendered_decision_table <- dcast(decisions_by_gender, Gender~`Decision Method`, value.var='Percentage', fill=0)
gendered_decision_table <- gendered_decision_table[,c("Gender", "Unanimous","Split", "Majority")]
kable(gendered_decision_table, align='l')


## Is Ring Rust Real?

ringrust_df <- fights[,c("event_date", "f1fid", "f2fid")]
ringrust_wins <- setDT(ringrust_df[,1:2]) %>% mutate(Result = "Win") %>% rename(Fighter_ID = f1fid)
ringrust_losses <- setDT(ringrust_df[,c(1,3)]) %>% mutate(Result = 'Loss') %>% rename(Fighter_ID = f2fid)

ringrust_df <- rbind(ringrust_wins, ringrust_losses) %>% 
  mutate(event_date = as.Date(event_date, format = '%m/%d/%Y')) %>% 
  arrange(event_date, desc(event_date)) %>%
  group_by(Fighter_ID) %>%
  mutate(LastFight = event_date - lag(event_date, default = event_date[1])) %>%
  filter(LastFight != 0) %>%
  mutate(LastFight = as.numeric(LastFight))

ringrust_barplot <- summarySE(ringrust_df, measurevar = "LastFight", groupvars="Result")
ggplot(ringrust_barplot, aes(x=Result, y=LastFight, fill=Result)) +
  geom_bar(stat='Identity', col="black") +
  geom_errorbar(aes(ymin=LastFight, ymax=LastFight+se), width=0.2) +
  scale_fill_manual(values=c(sunshine_over_glacier[1], sunshine_over_glacier[4])) +
  ylab('Days Since Last Fight') + ggtitle("Ring Rust") + theme_minimal()

pval <- t.test(as.numeric(LastFight)~Result, data=ringrust_df)
pval <- data.frame(pval$estimate[[1]], pval$estimate[[2]], formatC(pval$p.value, format = "e", digits = 2))

colnames(pval) <- c("Loss: Mean Days", "Win: Mean Days", "P-value")

kable(pval, row.names = F, align='l')


## Is There a Hometown Advantage in MMA?

fighters_loc <- fighters %>%
  mutate(Hometown = paste0(locality, ", ", country), Fighter_ID = fid) %>%
  dplyr::select(Hometown, Fighter_ID, Gender)


location_df <- setDT(fights) %>% dplyr::select(event_place,  f1fid, f2fid)
location_wins <- location_df[,c(1,2)] %>% mutate(Result = "Win") %>% dplyr::rename(Fighter_ID = f1fid)
location_losses <- location_df[,c(1,3)] %>% mutate(Result = "Loss") %>% dplyr::rename(Fighter_ID = f2fid)

location_df <- rbind(location_wins, location_losses) %>% setDT %>%
  mutate_if(is.factor, as.character) %>% rowwise() %>%
  mutate(Location = paste0(unlist(strsplit(event_place, split=", "))[2], ", ",
                           unlist(strsplit(event_place, split=", "))[3])) %>%
  dplyr::select(-event_place) %>%
  left_join(fighters_loc) %>% rowwise() %>%
  mutate(Hometown = paste0(unlist(strsplit(Hometown, split=", "))[1], ", ",
                           unlist(strsplit(Hometown, split=", "))[2])) %>%
  mutate(Local = as.character(Location == Hometown)) %>%
  mutate(Local=dplyr::recode(Local, `TRUE` = 'Home', `FALSE` = "Away")) %>%
  mutate(Result =  factor(Result, levels=c("Win", "Loss"))) %>%
  mutate(Local = factor(Local,levels=c("Home", 'Away')))


wins_by_hometown <- round(prop.table(table(location_df$Local,location_df$Result, dnn = list("Fighter", "Fight Result")),1)*100,1)

mosaic(wins_by_hometown, shade = TRUE, direction = "v", pop = FALSE, 
       gp = gpar(fill=matrix(c(sunshine_over_glacier[4], sunshine_over_glacier[1]), 2, 2)))
labeling_cells(text = as.table(wins_by_hometown), margin = 0)(as.table(wins_by_hometown))

kable(wins_by_hometown, align='l')



## The Land of Savages: Where do most UFC fighters come from?

US_fighters <- setDT(fighters) %>%
  dplyr::select(fid, locality, country) %>%
  filter(country %in% c("United States", "USA")) %>%
  mutate_if(is.factor, as.character) %>% rowwise() %>%
  mutate(id = unlist(strsplit(locality, split=", "))[2]) 

US_fighters$id <- revalue(US_fighters$id,
                          c("Lousiana" = "Louisiana","Massachusets" = "Massachusetts",
                            "Massachusettes" = "Massachusetts", "Phildelphia" = "Pennsylvania"))

US_fighters_count <- US_fighters %>% count(id) %>% arrange(desc(n))

us <- usa_composite()
us_map <- fortify(us, region="name")

ggplot() + geom_map(data=us_map, map=us_map,
                    aes(x=long, y=lat, map_id=id),
                    color="#2b2b2b", size=0.1, fill='grey') + theme_void() +
  geom_map(data=US_fighters_count, map=us_map, aes(fill=n, map_id = id), color='black', size=0.15) +
  scale_fill_gradientn(colors=rev(sunshine_over_glacier), name='', breaks=c(1,60,120,185), labels=c(0,60,120,185)) + coord_map() +
  ggtitle("Number of Fighters Per US State") + theme_void()


US_table <- US_fighters_count[1:10,]
colnames(US_table) <- c("State", "Number of Fighters")
kable(US_table[1:10,], row.names = F, align = 'l', caption = "Top 10 States with most UFC Fighters")



origin <- fighters %>% count(country, sort = T)

ggmap <- invisible(joinCountryData2Map(origin, joinCode='NAME', nameJoinColumn = "country"))
countrymatch_failure <- setdiff(origin$country, as.vector(na.omit(ggmap$country)))

fighters$country <- revalue(fighters$country, 
                            c("England" = "United Kingdom", "USA" = "United States", "Holland" = "Netherlands",
                              "Northern Ireland" = "United Kingdom", "Scotland" = "United Kingdom", "Finnland" = 'Finland'))

NonUS <- fighters %>% 
  count(country, sort = T) %>% 
  filter(!country %in% c("United States", ""))

world_map<-map_data("world")
ggplot() + geom_map(data=world_map, map=world_map,
                    aes(x=long, y=lat, map_id=region),
                    color="#2b2b2b", size=0.1, fill='grey') + theme_void() +
  geom_map(data=NonUS, map=world_map, aes(fill=n, map_id = country), color='black', size=0.15) +
  scale_fill_gradientn(colors=rev(sunshine_over_glacier), name='', breaks=c(1,50,100,150,199), labels=c(1,50,100,150,200)) +
  ggtitle("Where do Non-US MMA Fighters Come From?") + 
  expand_limits(x = world_map$long, y = world_map$lat) + coord_equal()


NonUS_table <- NonUS[1:10,]
colnames(NonUS_table) <- c("Country", "Number of Fighters")
kable(NonUS_table, row.names = F, align = 'l', caption = "Top 10 Countries with most UFC Fighters (Excluding USA)")



######################
# Supplementary Data #
######################


## Wins by Strikes

strikes <- setDT(fights) %>% 
  na.omit() %>%
  dplyr::select(Category, method_d, round) %>%
  filter(Category == "Strike") %>%
  count(method_d, round, sort = T) %>%
  mutate(Round = round)

strikes_order <- aggregate(strikes$n, by=list(Strikes = strikes$method_d), FUN=sum) %>% 
  arrange(x) %>% filter(x > 3) %>% pull(Strikes)


ggplot(strikes, aes(x=reorder(method_d,n), y=n, fill=Round)) +
  geom_bar(aes(fill=as.factor(Round)), stat='identity', position = position_stack(reverse = TRUE), col = 'black', width=0.85) + 
  coord_flip() + labs(x="Joint Lock Method", y="Count") + ggtitle("Types of Strike Finishes") +
  scale_fill_manual(values = sunshine_over_glacier) + theme_minimal() +
  scale_x_discrete(limits=strikes_order)


strikes_table <- aggregate(strikes$n, by=list(Strikes = strikes$method_d), FUN=sum) %>% 
  filter(x > 3) %>% arrange(desc(x)) %>%
  setNames(c("Strikes", "Count"))
kable(strikes_table, row.names = F, align='l')


## Wins by Choke

Choke <- setDT(fights) %>% 
  na.omit() %>%
  dplyr::select(Category, method_d, round) %>%
  filter(Category == "Choke") %>%
  count(method_d, round, sort = T) %>%
  mutate(Round = round)

Choke_order <- aggregate(Choke$n, by=list(Choke = Choke$method_d), FUN=sum) %>% 
  arrange(x) %>% filter(x > 3) %>% pull(Choke)

ggplot(Choke, aes(x=reorder(method_d,n), y=n, fill=Round)) +
  geom_bar(aes(fill=as.factor(Round)), stat='identity', position = position_stack(reverse = TRUE), col = 'black', width=0.85) + 
  coord_flip() + labs(x="Win Type", y="Count") + ggtitle("Types of Choke Finishes") +
  scale_fill_manual(values = sunshine_over_glacier) + theme_minimal() +
  scale_x_discrete(limits=Choke_order)

Choke_table <- aggregate(Choke$n, by=list(Choke = Choke$method_d), FUN=sum) %>% 
  filter(x > 3) %>% arrange(desc(x)) %>%
  setNames(c("Choke", "Count"))
kable(Choke_table, row.names = F, align='l')


## Wins by Joint Lock

joint_locks<- setDT(fights)%>% 
  na.omit() %>%
  dplyr::select(Category, method_d, round) %>%
  filter(Category == "JointLock") %>%
  count(method_d, round, sort = T) %>%
  mutate(Round=round)

jointlock_order <- aggregate(joint_locks$n, by=list(Jointlock = joint_locks$method_d), FUN=sum) %>% 
  arrange(x) %>% filter(x > 3) %>% pull(Jointlock)

ggplot(joint_locks, aes(x=reorder(method_d,n), y=n, fill=Round)) +
  geom_bar(aes(fill=as.factor(Round)), stat='identity', position = position_stack(reverse = TRUE), col = 'black', width=0.85) + 
  coord_flip() + labs(x="Joint Lock Method", y="Count") + ggtitle("Types of Joint Lock Finishes") +
  scale_fill_manual(values = sunshine_over_glacier) + theme_minimal() +
  scale_x_discrete(limits=jointlock_order)

joint_locks_table <- aggregate(joint_locks$n, by=list(joint_locks = joint_locks$method_d), FUN=sum) %>% 
  filter(x > 3) %>% arrange(desc(x)) %>%
  setNames(c("Joint Lock", "Count"))
kable(joint_locks_table, row.names = F, align='l')


## Wins by Stoppage


Stoppage <- setDT(fights) %>% 
  na.omit() %>%
  dplyr::select(Category, method_d, round) %>%
  filter(Category == "Stoppage") %>%
  count(method_d, round, sort = T) %>%
  mutate(Round = round)

Stoppage_order <- aggregate(Stoppage$n, by=list(Stoppage = Stoppage$method_d), FUN=sum) %>% 
  arrange(x) %>% pull(Stoppage)

ggplot(Stoppage, aes(x=reorder(method_d,n), y=n, fill=Round)) +
  geom_bar(aes(fill=as.factor(Round)), stat='identity', position = position_stack(reverse = TRUE), col = 'black', width=0.85) + 
  coord_flip() + labs(x="Win Type", y="Count") + ggtitle("Types of Stoppages") +
  scale_fill_manual(values = sunshine_over_glacier) + theme_minimal() +
  scale_x_discrete(limits=Stoppage_order)


Stoppage_table <- aggregate(Stoppage$n, by=list(Stoppage = Stoppage$method_d), FUN=sum) %>% 
  arrange(desc(x)) %>%
  setNames(c("Stoppage", "Count"))
kable(Stoppage_table, row.names = F, align='l')


## Wins by Miscellaneous Methods

misc <- setDT(fights) %>% 
  na.omit() %>%
  dplyr::select(Category, method_d, round) %>%
  filter(Category == "MISC") %>%
  count(method_d, round, sort = T) %>%
  mutate(Round = round)

misc_order <- aggregate(misc$n, by=list(Misc = misc$method_d), FUN=sum) %>% 
  arrange(x) %>% pull(Misc)

ggplot(misc, aes(x=reorder(method_d,n), y=n, fill=Round)) +
  geom_bar(aes(fill=as.factor(Round)), stat='identity', position = position_stack(reverse = TRUE), col = 'black', width=0.85) + 
  coord_flip() + labs(x="Win Type", y="Count") + ggtitle("Types of Miscellaneous Finishes") +
  scale_fill_manual(values = sunshine_over_glacier[c(1,3,4,5)]) + theme_minimal() +
  scale_x_discrete(limits=misc_order) + scale_y_continuous(breaks=c(0,5,10))

misc_table <- aggregate(misc$n, by=list(misc = misc$method_d), FUN=sum) %>% 
  arrange(desc(x)) %>%
  setNames(c("Misc Finish", "Count"))
kable(misc_table, row.names = F, align='l')


## Wins by Injury

injuries <- setDT(fights) %>% 
  na.omit() %>%
  dplyr::select(Category, method_d, round) %>%
  filter(Category == "Injury") %>%
  count(method_d, round, sort = T) %>%
  mutate(Round = round)

injuries_order <- aggregate(injuries$n, by=list(Injuries = injuries$method_d), FUN=sum) %>% 
  arrange(x) %>% pull(Injuries)

ggplot(injuries, aes(x=reorder(method_d,n), y=n, fill=Round)) +
  geom_bar(aes(fill=as.factor(Round)), stat='identity', position = position_stack(reverse = TRUE), col = 'black', width=0.85) + 
  coord_flip() + labs(x="Type of injury", y="Count") + ggtitle("Types of Injury Stoppages") +
  scale_fill_manual(values = sunshine_over_glacier[c(1,3,5)]) + theme_minimal() +
  scale_x_discrete(limits=injuries_order)


injuries_table <- aggregate(injuries$n, by=list(injuries = injuries$method_d), FUN=sum) %>% 
  arrange(desc(x)) %>%
  setNames(c("Injury", "Count"))
kable(injuries_table, row.names = F, align='l')