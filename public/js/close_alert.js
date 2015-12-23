if (typeof close_alert_success !== 'undefined') {
    $(close_alert_success).click(function(){
        $(alert_success).hide(1000);
    });
}

if (typeof close_alert_info !== 'undefined') {
    $(close_alert_info).click(function(){
        $(alert_info).hide(1000);
    });
}

if (typeof close_alert_warning !== 'undefined') {
    $(close_alert_warning).click(function(){
        $(alert_warning).hide(1000);
    });
}

if (typeof close_alert_danger !== 'undefined') {
    $(close_alert_danger).click(function(){
        $(alert_danger).hide(1000);
    });
}