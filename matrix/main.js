/* --------------------------------------------------------------------------------- */
angular.module('matrix', []);
/* --------------------------------------------------------------------------------- */
angular.module('matrix').controller('matrix_controller', ['$scope', '$http', function ($scope, $http) {
  $scope.radius_servers = [];
  $scope.realms = [];
  $scope.loading = true;

  $http({
    method  : 'GET',
    url     : 'https://monitor.eduroam.cz/matrix/data.json'
  })
  .then(function(response) {
    for(i in response.data) {
      if($scope.radius_servers.indexOf(response.data[i].host_name) == -1)
        $scope.radius_servers.push(response.data[i].host_name);

      if($scope.realms.indexOf(response.data[i].service_description) == -1)
        $scope.realms.push(response.data[i].service_description);
    }
    prepare_data($scope, response.data);
    $scope.loading = false;
    graph_heat_map($scope);
  });
}]);
/* --------------------------------------------------------------------------------- */
function prepare_data($scope, data)
{
  $scope.radius_servers.sort();
  $scope.graph_data = [];

  for(var i in data)
    $scope.graph_data.push({ row : $scope.radius_servers.indexOf(data[i].host_name), 
                            col : $scope.realms.indexOf(data[i].service_description),
                            value : data[i].service_state });

  for(var i in $scope.realms)
    $scope.realms[i] = $scope.realms[i].substring(1);     // remove "@"

  $scope.form_data = {}; 
  $scope.form_data.log_scale = true;
}
/* --------------------------------------------------------------------------------- */
/* --------------------------------------------------------------------------------- */
// --------------------------------------------------------------------------------------
// --------------------------------------------------------------------------------------
// draw heat map graph
// based on http://bl.ocks.org/ianyfchang/8119685
// --------------------------------------------------------------------------------------
function graph_heat_map($scope)
{
  // ==========================================================
  // right margin for timestamp
  var margin = { top: 220, right: 250, bottom: 5, left: 230 };
  var cellSize = 18;

  var col_number = $scope.realms.length;
  var row_number = $scope.radius_servers.length;

  var width = cellSize * col_number;
  var height = cellSize * row_number;

  // ==========================================================
  var service_group_base = "https://ermon2.cesnet.cz/monitoring/list/servicegroups#!/monitoring/list/services?servicegroup_name=";
  var host_base = "https://ermon2.cesnet.cz/monitoring/list/hosts#!/monitoring/host/show?host="
  var service_base = "https://ermon2.cesnet.cz/monitoring/host/services?host=alpha.ujf.cas.cz#!/monitoring/service/show?host="
  // ==========================================================

  var rowLabel = $scope.radius_servers;
  var colLabel = $scope.realms;

  var hcrow = [];
  var hccol = [];

  for(var item in $scope.radius_servers)
    hcrow.push(Number(item));

  for(var item in $scope.realms)
    hccol.push(Number(item));

  // ==========================================================

  var data = $scope.graph_data;
  var max = 99;     // TODO ?
  
  // ==========================================================

  if($scope.form_data.log_scale) {
    var colorScale = d3.scaleLog()
        .domain([1, max])
        .range([d3.interpolateBlues(0), d3.interpolateBlues(1)])
  }
  else {
    var colorScale = d3.scaleLinear()
        .domain([0, max])
        .range([d3.interpolateBlues(0), d3.interpolateBlues(1)])
  }

    // icingaweb2 colors
    var colors = [ "#44bb77", "#ffaa44", "#ff5566" ];
    colors[99] = "#77aaff";

  // ==========================================================
   
    var svg = d3.select("body").append("svg");

    svg = svg.attr("width", width + margin.left + margin.right)
        .attr("height", height + margin.top + margin.bottom)
        .append("g")
        .attr("transform", "translate(" + margin.left + "," + margin.top + ")");

  // ==========================================================

    // row tooltip
    var row_tip = d3.tip()
      .attr('class', 'd3-tip')
      .offset([-10, 0])
      .html(function(d) {
      return "<strong>server:</strong> <span style='color:red'>" + d + "</span>";
    })

    svg.call(row_tip);

  // ==========================================================

    // col tooltip
    var col_tip = d3.tip()
      .attr('class', 'd3-tip')
      .offset(function(d) {
        return [ - this.getComputedTextLength() / 2 - 15, 10];
      })
      .html(function(d) {
      return "<strong>návštěvník z instituce:</strong> <span style='color:red'>" + d + "</span>";
    })

    svg.call(col_tip);
    
  // ==========================================================
    
    // cell tooltip
    var cell_tip = d3.tip()
      .attr('class', 'd3-tip')
      .offset([-10, 0])
      .html(function(d) {
        return "<strong>server:</strong> " + $scope.radius_servers[d.row] + ", <strong>návštěvník z instituce:</strong> " + $scope.realms[d.col] +
               " <span style='color:red'>" + d.value + "</span>";
    })

    svg.call(cell_tip);

  // ==========================================================

    var rowLabels = svg.append("g")
        .selectAll(".rowLabelg")
        .data(rowLabel)
        .enter()
        .append("text")
        .text(function (d) { return d; })
        .attr("x", 0)
        .attr("y", function (d, i) { return hcrow.indexOf(i) * cellSize; })
        .style("text-anchor", "end")
        .attr("transform", "translate(-6," + cellSize + ")")
        .attr("class", function (d, i) { return "rowLabel mono r" + i; })
        .on('mouseover', row_tip.show)
        .on('mouseout', row_tip.hide)
        .on("click", function(d, i) { window.open(host_base + d); });

  // ==========================================================

    var colLabels = svg.append("g")
        .selectAll(".colLabelg")
        .data(colLabel)
        .enter()
        .append("text")
        .text(function (d) { return d; })
        .attr("x", 0)
        .attr("y", function (d, i) { return hccol.indexOf(i) * cellSize; })
        .style("text-anchor", "left")
        .attr("transform", "translate(" + cellSize  + ",-6) rotate (-90)")
        .attr("class",  function (d,i) { return "colLabel mono c" + i; })
        .on('mouseover', col_tip.show)
        .on('mouseout', col_tip.hide)
        .on("click", function(d, i) { window.open(service_group_base + d); });

  // ==========================================================

    var heatMap = svg.append("g").attr("class", "g3")
          .selectAll(".cellg")
          .data(data,function(d) { return d.row + ":" + d.col; })
          .enter()
          .append("rect")
          .attr("x", function(d) { return (hccol.indexOf(d.col)) * cellSize + 6; })     // compensate for labels
          .attr("y", function(d) { return (hcrow.indexOf(d.row)) * cellSize + 4; })     // compensate for labels
          .attr("class", function(d) { return "cell cell-border cr" + d.row + " cc" + d.col; })
          .attr("class", "clickable")
          .attr("width", cellSize - 1)
          .attr("height", cellSize - 1)
          .style("fill", function(d) { return colors[d.value]; })
          .on('mouseover', cell_tip.show)
          .on('mouseout', cell_tip.hide)
          .on("click", function(d, i) { window.open(service_base + $scope.radius_servers[d.row] + "&service=%40" + $scope.realms[d.col]); });

  // ==========================================================
}
/* --------------------------------------------------------------------------------- */
