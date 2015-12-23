<!DOCTYPE html> 
<html> 
<head> 
<meta http-equiv="content-type" content="text/html; charset=UTF-8" /> 
<meta http-equiv="content-language" content="ru-ru" /> 
<title>Deploy new staging server</title> 
<meta name="keywords" content="php, ajax, jquery, вывод логов" /> 
<meta name="description" content="Deploy new staging server" /> 
<script type='text/javascript' src='http://ajax.googleapis.com/ajax/libs/jquery/1.6.2/jquery.min.js'></script> 
<script type='text/javascript'> 
$(document).ready(function(){ 

        var t = 3; // интервал обновления в секундах      

        setInterval(function () { 
            $.ajax({ 
                url: 'log.php', 
                cache: true, 
                global: true, 
                success: function(html){ 
                        $('#log').html(html);
                        //$('html body').scrollTop($('body').height());
                }
           });
        }, t*1000); 
        
}); 
</script> 
</head> 
<body> 
<font color=#00FF00>In progress...</font><br>
<pre id="log"> 

</pre> 
</body> 
</html>
