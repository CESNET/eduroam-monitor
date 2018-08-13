<?xml version="1.0" encoding="ISO-8859-2"?>

<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  version="1.0">

  <xsl:output method="xml" encoding="ISO-8859-2"
    cdata-section-elements="Xdescription"
    indent="no"/>

  <xsl:template match="/">
    <xsl:apply-templates/>
  </xsl:template>

  <xsl:template match="institutions">
    <xsl:element name="kml">
      <xsl:attribute name="xmlns">http://earth.google.com/kml/2.1</xsl:attribute>
      <xsl:element name="Document">
        <xsl:element name="name">eduroam.cz</xsl:element>
        <xsl:element name="desription">Lokality pokryte eduroamem v cechcach</xsl:element>
        <xsl:element name="Style">
          <xsl:attribute name="id">style1</xsl:attribute>
          <xsl:element name="IconStyle">
            <xsl:element name="Icon">
              <xsl:element name="href">http://maps.google.com/mapfiles/ms/micons/blue-dot.png</xsl:element>
            </xsl:element>
          </xsl:element>
        </xsl:element>
        <xsl:apply-templates select="institution"/>
      </xsl:element>
    </xsl:element>
  </xsl:template>

  <xsl:template match="institution">
    <xsl:element name="Folder">
      <xsl:element name="name"><xsl:value-of select="org_name"/></xsl:element>
      <xsl:apply-templates select="location"/>      
    </xsl:element>
  </xsl:template>

  <xsl:template match="location">
    <xsl:element name="Placemark">
      <xsl:element name="name"><xsl:value-of select="../org_name"/></xsl:element>
      <xsl:element name="description"> <!--disable-output-escaping-->
      &lt;div class="adr"&gt;
        <xsl:if test="loc_name">&lt;span class="fn"&gt;<xsl:value-of select="loc_name"/>&lt;/span&gt;,</xsl:if>
        &lt;span class="street-address"&gt;<xsl:value-of select="address/street"/>&lt;/span&gt;,
        &lt;span class="locality"&gt;<xsl:value-of select="address/city"/>&lt;/span&gt;
      &lt;/div&gt;
      &lt;div class="essid"&gt;
        &lt;span class="label"&gt;essid:&lt;/span&gt;
        &lt;span class="essid"&gt;<xsl:value-of select="SSID"/>&lt;/span&gt;
      &lt;/div&gt;
      &lt;div class="encryption"&gt;
        &lt;span class="label"&gt;šifrování:&lt;/span&gt;
        &lt;span class="encryption"&gt;<xsl:value-of select="enc_level"/>&lt;/span&gt;
      &lt;/div&gt;
      &lt;div class="conectivity"&gt;
        &lt;span class="label"&gt;konektivita:&lt;/span&gt;
        &lt;span class="wired"&gt;<xsl:choose>
          <xsl:when test="wired='true'">WiFi a kabely</xsl:when>
          <xsl:otherwise>WiFi</xsl:otherwise>
        </xsl:choose>&lt;/span&gt;;
        &lt;span class="IPv6"&gt;<xsl:choose>
          <xsl:when test="IPv6='true'">IPv4+6</xsl:when>
          <xsl:otherwise>IPv4</xsl:otherwise>
        </xsl:choose>&lt;/span&gt;;
        &lt;span class="FW"&gt;<xsl:choose>
          <xsl:when test="port_restrict='true'">FW</xsl:when>
          <xsl:otherwise>žádný FW</xsl:otherwise>
        </xsl:choose>&lt;/span&gt; +
        &lt;span class="NAT"&gt;<xsl:choose>
          <xsl:when test="NAT='true'">NAT</xsl:when>
          <xsl:otherwise>veřejné adresy</xsl:otherwise>
        </xsl:choose>&lt;/span&gt; +
        &lt;span class="proxy"&gt;<xsl:choose>
          <xsl:when test="transp_proxy='true'">transp. proxy</xsl:when>
          <xsl:otherwise>žádná proxy</xsl:otherwise>
        </xsl:choose>&lt;/span&gt;
      &lt;/div&gt;
      &lt;div class="separator"&gt;&#160;&lt;/div&gt;
      &lt;div class="info"&gt;
        &lt;span class="info_url"&gt;&lt;a href="<xsl:value-of select="info_URL"/>"&gt;informace pro návštěvníky&lt;gt&gt;&lt;/span&gt;
      &lt;/div&gt;
      &lt;div class="separator"&gt;&#160;&lt;/div&gt;
      </xsl:element>
      <xsl:element name="styleUrl">#style1</xsl:element>
      <xsl:element name="Point">
        <xsl:element name="coordinates"><xsl:value-of select="longitude"/>, <xsl:value-of select="latitude"/></xsl:element>
      </xsl:element>
    </xsl:element>
  </xsl:template>

</xsl:stylesheet>