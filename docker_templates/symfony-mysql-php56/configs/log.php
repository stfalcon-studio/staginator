<?php 
error_reporting(0);
$fp = @file("log.txt"); 

    for($i=0; $i<=count($fp); $i++){
        echo $fp[$i];
    } 
?>
