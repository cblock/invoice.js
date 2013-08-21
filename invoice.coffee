#= require jquery
#= require globalize
#= require globalize.culture.de
#= require globalize.culture.en
#
# Note: The above dependencies are assumed to be available.
#
#
# jQuery plugin that helps printing an invoice in html format by splitting it
# intelligently over several pages.
#
# The html body needs to comply with a tag structure as follows
#
# <div class="page">
#   <div class="header first inner last">
#   ...
#   </div>
#  <div class="body">
#  ...
#  <table class="splittable">
#    <thead class="first">
#     ...
#    </thead>
#    <thead class="inner">
#     ...
#    </thead>
#    <tbody>
#      <tr class="line-item">
#        <td class="amount">12,22 €</td>
#      </tr>
#    </tbody>
#    <tfoot class="last">
#      ...
#    </tfoot>
#  </table>
#  </div>
#  <div class="footer first inner last">
#  ...
#  </div
# </div>
#
#
# Repeated elements:
# ------------------
# There are two types of css classes used to mark div tags:
# 1.) header      | body        | footer      -> determines where in the page the element should be placed (do not combine)
# 2.) first-page  | inner-pages | last-page   -> determines on which pages the element should appear (can be combined)
#                                                  default for header and body: "first-page"
#                                                  default for footer: "first-page inner-pages last-page")
#
# Table splitting:
# ---------------
# Tables marked as "splittable" are automatically splitted across several pages if they do not fit into one page:
# 1.) tbody and tfooter elements can be marked with "first-page", "inner-pages", "last-page" (see above) to control occurrence
# 2.) td classes marked with "amount" are summed up automatically into a "running-total" and / or "carry-over"
# 3.) a thead > th element marked with "carry-over" is automatically filled in with the previous page's table running-total
# 4.) a tfoot > td element marked with "running-total" is automatically filled in with the running-total of the table
#     (including all running totals of all previous page tables)
#
# Page numbering:
# ---------------
# 1.) Nodes with class "page-number" are assigned the current page number
# 2.) Nodes with class "page-count" are assigned the total page count
#
#
# Notes:
# ----
# 1.) HTML spec allows only one thead, tbody, and tfoot element per table. Thus if a page is assigned several such
#     elements their inner html will be merged into a single thead/tbody/tfoot elements.
#     The merge operation leaves the original element order untouched.
# 2.) Plugin currently assumes A4 Layout with 1123 px / 297 mm page height
#
#
# Author:   Carsten Block
# Version:  1.0
# Website:  http://www.block-consult.com
#

jQuery ->
  $.PrintLayout = (element, options) ->
    @$original = $(element)        # jQuery version of DOM element attached to the plugin
    @$target                       # jQuery version of DOM element that contains the processed (paged) html output
    @curr_page = 1                 # current page being processed
    @page_count = 0                # number of pages required to fit the body content
    @heights = {}
    #@debug = true

    @init = =>
      Globalize.culture('de')
      @$target = init_target_container(@$original)
      @heights = calc_heights(@$original)
      #debug JSON.stringify(@heights,null,2)
      @page_count = calc_page_count()
      #debug "Pages: #{@page_count}"
      assemble_pages()
      @$original.remove()
      update_running_totals()


    # sets up the target dom node that will later contain all processed (i.e. paginated) html
    init_target_container = ($parent_elem) =>
      $parent_elem.after('<div id="processed-pages"></div>')
      $new_elem = $('#processed-pages')
      #$new_elem.after('<div id="debug-output" style="page-break-before: true; border: 1px solid #999; padding: 5px"></div>') if @debug
      $new_elem

    #debug = (text) =>
    #  $('#debug-output').append("<pre>#{text}</pre>") if @debug

    # calculates the heights of all header, footer and body types and stores them in the class variable @heights
    calc_heights = ($parent_elem) ->
      heights =
        page:
          available: calc_page_height($parent_elem)
          header:
            'single-page': height_of('.row.header.single-page', $parent_elem)
            'first-page': height_of('.row.header.first-page', $parent_elem)
            'inner-pages': height_of('.row.header.inner-pages', $parent_elem)
            'last-page': height_of('.row.header.last-page', $parent_elem)
          footer:
            'single-page': height_of('.row.footer.single-page', $parent_elem)
            'first-page': height_of('.row.footer.first-page', $parent_elem)
            'inner-pages': height_of('.row.footer.inner-pages', $parent_elem)
            'last-page': height_of('.row.footer.last-page', $parent_elem)
          body:
            'contents-height': height_of('.row.body:not(.row-body-table)', $parent_elem) #height of all row body divs other than those with tables in. table rows are accounted for in @heights.table['contents-height']
        table:
          'contents-height': height_of('table.splittable', $parent_elem)
          header:
            'single-page': height_of('.splittable thead.single-page', $parent_elem)
            'first-page': height_of('.splittable thead.first-page', $parent_elem)
            'inner-pages': height_of('.splittable thead.inner-pages', $parent_elem)
            'last-page': height_of('.splittable thead.last-page', $parent_elem)
          footer:
            'single-page': height_of('.splittable tfoot.single-page', $parent_elem)
            'first-page': height_of('.splittable tfoot.first-page', $parent_elem)
            'inner-pages': height_of('.splittable tfoot.inner-pages', $parent_elem)
            'last-page': height_of('.splittable tfoot.last-page', $parent_elem)
          body: height_of('.splittable tbody', $parent_elem)

      heights.page.body.available =
        'single-page': heights.page.available - heights.page.header['single-page'] - heights.page.footer['single-page']
        'first-page': heights.page.available - heights.page.header['first-page'] - heights.page.footer['first-page']
        'inner-pages': heights.page.available - heights.page.header['inner-pages'] - heights.page.footer['inner-pages']
        'last-page': heights.page.available - heights.page.header['last-page'] - heights.page.footer['last-page']

      heights

    # calculates the height of a single page by temporarily adding a dummy node with class ".page" to the dom
    # and measuring its height
    calc_page_height = ($parent_elem) ->
      id="389je29894if"
      $parent_elem.append("<div id='#{id}' class='page'></div>")
      $test_element = $("##{id}")
      page_height = $test_element.height()
      $test_element.remove()
      page_height


    # Calculates aggregate jQuery#outerHeight (including margins) for all given dom elements
    # Note: jQuery#outerHeight by default calculates height only for the first element in the matching set,
    # thus we lopp through all matching node elements adding up their respective heights and return the total height
    #
    # @param selector either a jQuery object or a valid css selector
    height_of = (selector, $parent_elem) ->
      $elements = if selector instanceof jQuery then selector else $(selector)
      height = 0
      $parent_elem.find($elements).each (i, el) ->
        height += Math.round($(el).outerHeight(true))
      height


    #calculates the overall number of print pages required to display the content
    calc_page_count = () =>
      contents_height = @heights.page.body['contents-height'] + @heights.table['contents-height']
      #debug "calc_page_count with overall contents_height: #{contents_height} (body_height: #{@heights.page.body['contents-height']} + table height: #{@heights.table['contents-height']})"

      #shortcut: all contents fits into a single page
      if @heights.page.body.available['single-page'] >= contents_height
        #debug "All contents fits into a single page: page.body.available['single-page]: (#{@heights.page.body.available['single-page']} >= contents_height: #{contents_height})"
        return 1

      #we need more than one page...
      page_count = 0
      while contents_height > 0
        if page_count == 0
          contents_height -= @heights.page.body.available['first-page']
        else
          if @heights.page.body.available['last-page'] >= contents_height
            contents_height = 0
          else
            contents_height -= @heights.page.body.available['inner-pages']
        page_count += 1
      page_count


    # Creates a paged html page out of the original unibody html page
    assemble_pages = () =>
      page = 1
      if @page_count == 1
        assemble_page('single-page', page)
      else
        while (page <= @page_count)
          switch page
            when 1 then page_type = 'first-page'
            when @page_count then page_type = 'last-page'
            else page_type = 'inner-pages'
          assemble_page(page_type, page)
          page +=1


    # Assembles a single page which consists of one or more header, body, and footer elements
    #
    # Nodes marked with class '.page-number' are filled in with the current page number
    # Nodes marked with class '.page-count' are filled in with the overall page number
    assemble_page = (page_type, page_number) =>
      #debug "assemble_page(page_type: #{page_type}, page_number: #{page_number})"
      $new_page = $('<div class="page"></div>')
      $new_page.append(@$original.find(".row.header.#{page_type}").clone())
      $new_page.append(assemble_body(page_type))
      $new_page.append(@$original.find(".row.footer.#{page_type}").clone())
      $new_page.find('.page-number').text(page_number)
      $new_page.find('.page-count').text(@page_count)
      @$target.append($new_page)



    # creates a page specific "body" area by subsequently moving dom nodes with class "body" from @$original into @$target
    # ensuring that the target page has enough vertical space to display the respective node
    #
    # Special case: node to be moved is to large for the target space but contains a "table.splittable" -> invoke split table logic
    #
    # Note: this method actually moves nodes instead of cloning them in order not to add body elements to more than one page
    assemble_body = (page_type) =>
      #debug ("assemble body called for page type '#{page_type}'")
      $adjusted_body = $('<div></div>')
      available_body_height = @heights.page.body.available[page_type]
      $body_elems = @$original.find('.row.body')

      $body_elems.each (i, el) =>
        $el = $(el)
        el_height = $el.outerHeight(true)
        $table = $el.find('table.splittable')
        if ($table.size())
          $adjusted_table = adjust_table($table, available_body_height)
          if ($adjusted_table)
            available_body_height -= $adjusted_table.outerHeight(true)
            $adjusted_body.append($adjusted_table)
        else if available_body_height >= el_height
          $adjusted_body.append($el)
          available_body_height -= el_height
          true
        else
          false
      $adjusted_body.children()

    # Takes the given table returns a new table node by
    # 1.) Cloning appropriate <thead> contents from the given table into the new table based on the table's table state
    # 2.) Moving as many rows from the given table's <tbody> into the new table as can be fit into the available_body_height
    # 3.) Cloning appropriate <tfoot> contents from the given table into the new table based on the table's table state
    #
    # Note: This method manipulates $table element by adding a "data-table-state" attribute to persist table_state acrosse method calls
    adjust_table = ($table, available_body_height) =>

      table_state = determine_table_state($table, available_body_height)
      #debug "split table called with available_body_height: #{available_body_height}, table_state: #{table_state}"
      available_body_height -= @heights.table.header[table_state]
      available_body_height -= @heights.table.footer[table_state]
      current_body_height = $table.find('tbody tr').first().outerHeight(true) || 0
      #debug "available table body height after header and footer adjustment: #{available_body_height}, current table body height: #{current_body_height}"
      if available_body_height > current_body_height
        #debug("enough space to fit at least one table row into this page")
        $adjusted_table = $('<table class="splittable"></table>')

        $headers = assemble_table_header($table, table_state)
        $footers = assemble_table_footer($table, table_state)
        $body = assemble_table_body($table, table_state, available_body_height)

        $adjusted_table.append($headers)
        $adjusted_table.append($body)
        $adjusted_table.append($footers)
        $table.data('table-state', 'inner-pages')
        $adjusted_table
      else #not even enough vertical space to fit table headers into the page
        #debug("not enough space to fit at least one table row into this page")
        return null

    # Determines the given table's table state as one of 'first-page', 'inner-pages', 'last-page'
    determine_table_state = ($table, available_body_height) =>
      stored_state = $table.data('table-state')
      table_height = $table.outerHeight(true)
      #debug "determine table state with stored_state: #{stored_state}, table_height: #{table_height}, available_body_height: #{available_body_height}"
      if available_body_height >= table_height
        table_state = 'last-page'
        #debug "table fits into page completely -> last-page"
      else if stored_state
        table_state = stored_state
        #debug "stored_state found -> #{stored_state}"
      else
        #debug "set to first_state}"
        table_state = 'first-page'
      $table.data('table-state', table_state)
      table_state


    #Returns cloned thead -> tr rows that match the provided table_page_type
    assemble_table_header = ($table, table_page_type) =>
      $thead = $('<thead></thead>')
      $thead.append($table.find("thead.#{table_page_type} tr").clone())

    #Returns cloned tfoot-> tr rows that match the provided table_page_type
    assemble_table_footer = ($table, table_page_type) =>
      $tfoot = $('<tfoot></tfoot>')
      $tfoot.append($table.find("tfoot.#{table_page_type} tr").clone())

    # Returns a new tbody dom node that contains as many *moved* tbody -> tr rows from
    # the given table as can be fit into the given max_height
    assemble_table_body = ($table, table_page_type, max_height) =>
      $tbody = $('<tbody></tbody>')

      #do not clone so we can actually 'move' rows from old page to new page
      $table.find('tbody tr').each (i, row) =>
        $row = $(row)
        row_height = $row.outerHeight(true)
        if (max_height >= row_height)
          #debug("table_page_type: #{table_page_type}, row #{i+1} height: #{row_height}, remaining available body height: #{max_height} -> append")
          $tbody.append($row);
          max_height -= row_height
          true
        else
          #debug("row #{i+1} height: #{row_height}, remaining height: #{max_height} -> skip")
          false
      $tbody


    # Updates running totals and carry-overs in all tables of the newly assembled paged html by summing
    # up all numeric values found in td.amount cells across all tables
    #
    # The algorithm walks top down through all tables and...
    # 1.)
    #   a.) Removes any tr.carry-over rows from the current table if running-total == 0 or...
    #   b.) Sets td.carry-over cell text to the running-total of the preceding table if running-total > 0
    # # 2.) Sums up all td.amount elements of the current table including carry-over from previous table
    # 3.) Sets td.running-total to accumulated amount of the current_table including carry-over from previous tables
    #
    # Note: td.running-total and td.carry-over elemenets may occur several times in a table without influencing calculation
    update_running_totals = () =>
      running_total = 0
      @$target.find('.page table.splittable').each (i, table) ->
        $table = $(table)
        if running_total == 0
          $table.find('tr.carry-over').remove()
        else
          $table.find('td.carry-over').text((Globalize.format(running_total, 'n2')) + ' €')
        table_total = running_total
        $table.find('td.amount').each (i, td) ->
          table_total += parse_number(td.innerText)
        if table_total == 0
          $table.find('tr.running-total').remove()
        else
          $table.find('td.running-total').text((Globalize.format(table_total, 'n2')) + ' €')
        running_total = table_total
      null


    #takes a css selector or a jQuery object and tries to parse the object's value as number using Globalize float parser
    parse_number_from_elem = (el) ->
      v = if el instanceof jQuery then el.val() else $(el).val()
      parse_number(v)


    #takes a string value and tries to parse a number out of it using Globalize float parser
    parse_number = (val) ->
      val = Math.round(Globalize.parseFloat(val) * 100) / 100 if val
      if $.isNumeric(val) then val else 0

  # initialise the plugin
    @init()

    this

  # set up jquery plugin
  $.fn.formatForPrint = (options) ->
    this.each ->
      if $(this).data('printLayout') is undefined
        plugin = new $.PrintLayout(this, options)
        $(this).data('printLayout', plugin)

  $('#raw-page').formatForPrint()
