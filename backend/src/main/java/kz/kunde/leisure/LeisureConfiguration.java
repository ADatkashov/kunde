package kz.kunde.leisure;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Configuration;

@Configuration
@EnableConfigurationProperties(LeisureProperties.class)
public class LeisureConfiguration {}
