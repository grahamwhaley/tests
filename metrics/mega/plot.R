#!/usr/bin/env Rscript

library('ggplot2')
library('gridExtra')

#file1='results-runc-busybox.csv'
file1='results-cor-busybox.csv'
file1name='busybox'
#file2='results-runc-nginx.csv'
file2='results-cor-nginx.csv'
file2name='nginx'
#file3='results-runc-alpine.csv'
file3='results-cor-alpine.csv'
file3name='alpine'
#file4='results-runc-mysql.csv'
file4='results-cor-mysql.csv'
file4name='mysql'

#data2 = read.table('burndown_2.txt')
runc_data = read.table(file1, header=TRUE, sep=",")
cor_data = read.table(file2, header=TRUE, sep=",")
three_data = read.table(file3, header=TRUE, sep=",")
four_data = read.table(file4, header=TRUE, sep=",")

runc_frame = data.frame(group=rep(file1name, length(runc_data$number)), number=runc_data$number, time=runc_data$time, avail=runc_data$available )
cor_frame = data.frame(group=rep(file2name, length(cor_data$number)), number=cor_data$number, time=cor_data$time, avail=cor_data$available )
three_frame = data.frame(group=rep(file3name, length(three_data$number)), number=three_data$number, time=three_data$time, avail=three_data$available )
four_frame = data.frame(group=rep(file4name, length(four_data$number)), number=four_data$number, time=four_data$time, avail=four_data$available )

full_frame = rbind(runc_frame, cor_frame, three_frame, four_frame)

timeplot <- ggplot() +
  geom_line(data=full_frame, aes(number, time, colour=group)) +
  xlab('Containers') +
  ylab('exec time') +
  ylim(0, NA)

availplot <- ggplot() +
  geom_line(data=full_frame, aes(number, avail, colour=group)) +
  xlab('Containers') +
  ylab('mem avail')
#  ylim(0, NA)


# HD 1920x1080 image @ 120dpi
#  
#ggsave('plot.png', plot=timeplot, width=16, height=9, dpi=120)
#ggsave('plot2.png', plot=availplot, width=16, height=9, dpi=300)

master_plot = grid.arrange(
	timeplot,
	availplot,
	nrow=2,
	ncol=1 )

ggsave('combined.png', plot=master_plot, width=16, height=9, dpi=120)
