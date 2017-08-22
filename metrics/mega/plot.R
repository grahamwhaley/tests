#!/usr/bin/env Rscript

library('ggplot2')
library('gridExtra')

#data2 = read.table('burndown_2.txt')
runc_data = read.table('results-runc-busybox.csv', header=TRUE, sep=",")
cor_data = read.table('results-cor-busybox.csv', header=TRUE, sep=",")

runc_frame = data.frame(group=rep("runc", length(runc_data$number)), number=runc_data$number, time=runc_data$time, avail=runc_data$available )
cor_frame = data.frame(group=rep("cor", length(cor_data$number)), number=cor_data$number, time=cor_data$time, avail=cor_data$available )

full_frame = rbind(runc_frame, cor_frame)

timeplot <- ggplot() +
  geom_line(data=full_frame, aes(number, time, colour=group)) +
  xlab('Containers') +
  ylab('exec time') +
  ylim(0, NA)

availplot <- ggplot() +
  geom_line(data=full_frame, aes(number, avail, colour=group)) +
  xlab('Containers') +
  ylab('mem avail') +
  ylim(0, NA)


# HD 1920x1080 image @ 120dpi
#  
ggsave('plot.png', plot=timeplot, width=16, height=9, dpi=120)
ggsave('plot2.png', plot=availplot, width=16, height=9, dpi=300)

master_plot = grid.arrange(
	timeplot,
	availplot,
	nrow=1,
	ncol=2 )

ggsave('combined.png', plot=master_plot, width=16, height=9, dpi=120)
