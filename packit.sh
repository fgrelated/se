#!/bin/bash
rm -f parse-speakeasy.rb.html
beautify parse-speakeasy.rb
zip parse-speakeasy-$(date +%s).zip parse-speakeasy.rb*
zip speakeasy-$(date +%s).zip *.html
